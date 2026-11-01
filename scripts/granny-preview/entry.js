// App-specific static preview adapter. Upstream source is MIT; see LICENSE.
import { parseGR2File } from 'granny-ro-js/GrannyFile.js';
import { loadGR2, parseTypeTree, parseObject } from 'granny-ro-js/GrannyTypeTree.js';
import { extractMeshes } from 'granny-ro-js/GrannyMesh.js';
import { extractSkeletons } from 'granny-ro-js/GrannySkeleton.js';
import { extractModels } from 'granny-ro-js/GrannyModel.js';
import { extractAnimations } from 'granny-ro-js/GrannyAnimation.js';
import { composeLocalMatrix, poseSkeletonAt } from 'granny-ro-js/GrannyPose.js';
import { walkTextureImages } from 'granny-ro-js/GrannyTexture.js';
import { decodeIGCTexture } from 'granny-ro-js/GrannyTextureIGC.js';

const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function decode64(text) {
    const output = new Uint8Array((text.length / 4) * 3 - (text.endsWith('==') ? 2 : text.endsWith('=') ? 1 : 0));
    let n = 0;
    for (let i = 0; i < text.length; i += 4) {
        const bits = (alphabet.indexOf(text[i]) << 18) | (alphabet.indexOf(text[i+1]) << 12) | (Math.max(0,alphabet.indexOf(text[i+2])) << 6) | Math.max(0,alphabet.indexOf(text[i+3]));
        if (n < output.length) output[n++] = bits >>> 16;
        if (n < output.length) output[n++] = bits >>> 8;
        if (n < output.length) output[n++] = bits;
    }
    return output;
}
function encode64(bytes) {
    const chunks = []; let text = '';
    for (let i = 0; i < bytes.length; i += 3) {
        const bits = (bytes[i] << 16) | ((bytes[i+1] ?? 0) << 8) | (bytes[i+2] ?? 0);
        text += alphabet[(bits >>> 18) & 63] + alphabet[(bits >>> 12) & 63] + (i+1 < bytes.length ? alphabet[(bits >>> 6) & 63] : '=') + (i+2 < bytes.length ? alphabet[bits & 63] : '=');
        if (text.length >= 16384) { chunks.push(text); text = ''; }
    }
    chunks.push(text); return chunks.join('');
}
function load(input) {
    const file = parseGR2File(decode64(input.file));
    // Swift has already validated and decompressed these sections. Keep the
    // original file for fixup tables; only replace the section-byte provider.
    const sections = input.sections.map(decode64);
    file.sectionBytes = section => sections[section.index];
    for (const section of file.sections) section.compression = 0;
    const loaded = loadGR2(file);
    const root = parseObject(loaded, parseTypeTree(loaded, file.header.root_type), file.header.root_object);
    const art = root.ArtToolInfo;
    const artFields = art?.target && art?.reference_type ? parseObject(loaded, parseTypeTree(loaded, [art.reference_type.section, art.reference_type.offset]), [art.target.section, art.target.offset]) : {};
    return { loaded, root, artFields };
}
function point(matrix, position) {
    const [x,y,z] = position;
    return [matrix[0]*x+matrix[4]*y+matrix[8]*z+matrix[12], matrix[1]*x+matrix[5]*y+matrix[9]*z+matrix[13], matrix[2]*x+matrix[6]*y+matrix[10]*z+matrix[14]];
}
export function preview(input, companion) {
    const selected = load(input), source = companion ? load(companion) : selected;
    const {loaded, root, artFields} = source;
    if ((root.Meshes?.count ?? 0) > 128 || (root.Textures?.count ?? 0) > 128 || (root.Skeletons?.count ?? 0) > 16) throw Error('GR2 scene exceeds the model preview limits.');
    const meshes = extractMeshes(loaded, {maxMeshes:128}), skeletons = extractSkeletons(loaded, {maxSkeletons:16, maxBones:4096});
    const models = extractModels(loaded, {maxModels:128, maxBindings:128});
    const notes = [], missing = [], textures = [];
    let animation = null;
    try { animation = extractAnimations(selected.loaded, {maxAnimations:1})[0] ?? null; }
    catch (error) { notes.push('Animation could not be sampled; showing bind pose: ' + error.message); }
    if (companion) notes.push('Matched model: ' + companion.path);
    notes.push(animation ? 'Static first animation frame; animation playback is not enabled.' : 'Static bind pose; animation playback is not enabled.');
    const poses = skeletons.map(s => poseSkeletonAt(s, animation, 0));
    let pixelCount = 0;
    for (const record of walkTextureImages(loaded, {maxTextures:128,maxImages:1,maxMips:1})) {
        const key = 'gr2-texture-' + record.texIdx;
        try {
            const w = record.width, h = record.height;
            if (!Number.isInteger(w) || !Number.isInteger(h) || w <= 0 || h <= 0 || w > 4096 || h > 4096 || pixelCount + w*h > 8*1024*1024) throw Error('texture exceeds preview limit');
            pixelCount += w*h;
            let pixels;
            if (record.encoding === 3) pixels = decodeIGCTexture({Width:w, Height:h, Alpha:record.alpha, ImageData:record.pixelBytes});
            else if (record.encoding === 1 && record.pixelBytes?.length === w*h*4) {
                pixels = new Uint8Array(w*h*4);
                for (let p = 0; p < pixels.length; p += 4) { pixels[p] = record.pixelBytes[p+2]; pixels[p+1] = record.pixelBytes[p+1]; pixels[p+2] = record.pixelBytes[p]; pixels[p+3] = record.pixelBytes[p+3]; }
            } else throw Error('unsupported texture encoding ' + record.encoding);
            textures.push({key, width:w, height:h, rgba:encode64(pixels), name:record.fromFileName});
        } catch (error) { missing.push(key + ': ' + error.message); }
    }
    const result = []; let vertices = 0, triangles = 0;
    const transformMesh = (mesh, model) => {
        vertices += mesh.positions.length; triangles += mesh.indices.length / 3;
        if (vertices > 500000 || triangles > 1000000) throw Error('GR2 geometry exceeds preview limits.');
        const skeletonIndex = model?.skeletonIdx ?? 0, skeleton = skeletons[skeletonIndex], pose = poses[skeletonIndex];
        const boneIndices = skeleton ? new Map(skeleton.bones.map((b,i)=>[b.name,i])) : new Map();
        const placement = composeLocalMatrix(model?.initialPlacement);
        const positions = mesh.positions.map((position,i) => {
            const weights = mesh.vertexWeights[i] ?? []; let sum = 0; const skinned = [0,0,0];
            for (const binding of weights) {
                const boneIndex = boneIndices.get(mesh.boneBindings[binding.boneIndex]?.name), matrix = pose?.skinningMatrices[boneIndex];
                if (!matrix) continue;
                const p = point(matrix, position); sum += binding.weight;
                for (let axis=0;axis<3;axis++) skinned[axis] += p[axis]*binding.weight;
            }
            return point(placement, sum > 0 ? skinned.map(v=>v/sum) : position);
        });
        const materials = mesh.materials.map(() => '');
        // Material indices are global material indices, not texture indices.
        // Resolve texture paths against the texture table explicitly.
        for (let i=0;i<materials.length;i++) {
            const texture = textures.find(t=>t.name === mesh.materials[i].textureFile);
            materials[i] = texture?.key ?? '';
            if (!texture && mesh.materials[i].textureFile) missing.push(mesh.materials[i].textureFile + ' (texture unavailable)');
        }
        result.push({name:mesh.name, positions, indices:mesh.indices, uvs:mesh.uvs, materials, groups:mesh.triangleGroups});
    };
    const included = new Set();
    for (const model of models) for (const binding of model.meshBindings) {
        const mesh = meshes[binding.meshIdx]; if (!mesh) continue;
        transformMesh(mesh,model); included.add(binding.meshIdx);
    }
    for (let i=0;i<meshes.length;i++) if (!included.has(i)) transformMesh(meshes[i],null);
    let upAxis = [0,0,1];
    if (root.ArtToolInfo?.target && artFields.UpVector) {
        const data = loaded.sectionsOriginal[root.ArtToolInfo.target.section];
        const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
        upAxis = [0,1,2].map(i=>view.getFloat32(artFields.UpVector.offset+i*4,true));
    }
    return JSON.stringify({meshes:result, textures, missing:[...new Set(missing)], notes, upAxis, skeletonCount:skeletons.length, boneCount:skeletons.reduce((n,s)=>n+s.bones.length,0), animationName:animation?.name ?? ''});
}
