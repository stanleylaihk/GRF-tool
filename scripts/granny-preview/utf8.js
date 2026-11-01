// JavaScriptCore supplies typed arrays but not the browser TextDecoder API.
export class TextDecoder {
    decode(bytes) {
        let text = '';
        for (let i = 0; i < bytes.length;) {
            const first = bytes[i++];
            if (first < 128) { text += String.fromCharCode(first); continue; }
            const count = first >= 240 && first <= 244 ? 3 : first >= 224 && first <= 239 ? 2 : first >= 194 && first <= 223 ? 1 : 0;
            if (!count || i + count > bytes.length) { text += '\uFFFD'; continue; }
            let point = first & (0x7f >> count), valid = true;
            for (let n = 0; n < count; n++) {
                if ((bytes[i + n] & 192) !== 128) { valid = false; break; }
                point = (point << 6) | (bytes[i + n] & 63);
            }
            if (!valid || point < [0,128,2048,65536][count] || point > 0x10ffff || point >= 0xd800 && point <= 0xdfff) { text += '\uFFFD'; continue; }
            i += count; text += String.fromCodePoint(point);
        }
        return text;
    }
}
