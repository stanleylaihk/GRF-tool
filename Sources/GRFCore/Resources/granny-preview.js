var GRFGranny = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // scripts/granny-preview/entry.js
  var entry_exports = {};
  __export(entry_exports, {
    preview: () => preview
  });

  // scripts/granny-preview/utf8.js
  var TextDecoder = class {
    decode(bytes) {
      let text = "";
      for (let i = 0; i < bytes.length; ) {
        const first = bytes[i++];
        if (first < 128) {
          text += String.fromCharCode(first);
          continue;
        }
        const count = first >= 240 && first <= 244 ? 3 : first >= 224 && first <= 239 ? 2 : first >= 194 && first <= 223 ? 1 : 0;
        if (!count || i + count > bytes.length) {
          text += "\uFFFD";
          continue;
        }
        let point2 = first & 127 >> count, valid = true;
        for (let n = 0; n < count; n++) {
          if ((bytes[i + n] & 192) !== 128) {
            valid = false;
            break;
          }
          point2 = point2 << 6 | bytes[i + n] & 63;
        }
        if (!valid || point2 < [0, 128, 2048, 65536][count] || point2 > 1114111 || point2 >= 55296 && point2 <= 57343) {
          text += "\uFFFD";
          continue;
        }
        i += count;
        text += String.fromCodePoint(point2);
      }
      return text;
    }
  };

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/GrannyFile.js
  var MAGIC_OLD = [3400558520, 263286264, 2123133572, 503322974];
  var MAGIC_32LE = [3228360233, 726901946, 2780296485, 4007814902];
  var MAGIC_32BE = [3046445326, 1270195562, 1344809195, 78870565];
  var MAGIC_64LE = [1581882341, 337601391, 2850755358, 3303915152];
  var MAGIC_64BE = [3822359857, 1649400864, 986724044, 2315223729];
  var MAGIC_SIZE = 32;
  var SECTION_RECORD_SIZE = 44;
  var EXTRA_TAG_COUNT = 4;
  var COMPRESSION_NONE = 0;
  var COMPRESSION_OODLE0 = 1;
  var COMPRESSION_NAMES = {
    0: "none",
    1: "oodle0",
    2: "oodle1",
    3: "bitknit",
    4: "bitknit2"
  };
  var SECTION_NAMES = {
    0: "main",
    1: "rigid_vertex",
    2: "rigid_index",
    3: "deformable_vertex",
    4: "deformable_index",
    5: "texture",
    6: "discardable",
    7: "unloaded"
  };
  function swapU32(value) {
    const v = value >>> 0;
    return ((v & 255) << 24 | (v & 65280) << 8 | (v & 16711680) >>> 8 | (v & 4278190080) >>> 24) >>> 0;
  }
  function arrayEq(a, b) {
    const len = a.length;
    if (len !== b.length) return false;
    for (let i = 0; i < len; i++) if (a[i] !== b[i]) return false;
    return true;
  }
  function magicWords(view, byteReversed) {
    const w = [
      view.getUint32(0, true),
      view.getUint32(4, true),
      view.getUint32(8, true),
      view.getUint32(12, true)
    ];
    if (!byteReversed) return w;
    for (let i = 0; i < 4; i++) w[i] = swapU32(w[i]);
    return w;
  }
  function detectGR2(buffer) {
    const view = bufferView(buffer);
    if (view.byteLength < MAGIC_SIZE) {
      return { ok: false, byteReversed: false, pointerSize: 0 };
    }
    const little = magicWords(view, false);
    if (arrayEq(little, MAGIC_OLD) || arrayEq(little, MAGIC_32LE)) {
      return { ok: true, byteReversed: false, pointerSize: 32 };
    }
    if (arrayEq(little, MAGIC_64LE)) {
      return { ok: true, byteReversed: false, pointerSize: 64 };
    }
    const swapped = little.map(swapU32);
    if (arrayEq(swapped, MAGIC_OLD) || arrayEq(swapped, MAGIC_32BE)) {
      return { ok: true, byteReversed: true, pointerSize: 32 };
    }
    if (arrayEq(swapped, MAGIC_64BE)) {
      return { ok: true, byteReversed: true, pointerSize: 64 };
    }
    return { ok: false, byteReversed: false, pointerSize: 0 };
  }
  function bufferView(buffer) {
    if (buffer instanceof DataView) return buffer;
    if (ArrayBuffer.isView(buffer)) {
      return new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    }
    if (buffer instanceof ArrayBuffer) return new DataView(buffer);
    throw new TypeError("parseGR2File expects ArrayBuffer, DataView or typed array");
  }
  function bufferBytes(buffer) {
    if (buffer instanceof Uint8Array) return buffer;
    if (ArrayBuffer.isView(buffer)) {
      return new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    }
    if (buffer instanceof ArrayBuffer) return new Uint8Array(buffer);
    throw new TypeError("parseGR2File expects ArrayBuffer, DataView or typed array");
  }
  function makeReader(view, byteReversed) {
    const little = !byteReversed;
    const cap = view.byteLength;
    return (offset) => {
      if (offset < 0 || offset + 4 > cap) {
        throw new RangeError(`gr2 read out of range at 0x${offset.toString(16)} (cap 0x${cap.toString(16)})`);
      }
      return view.getUint32(offset, little);
    };
  }
  function parseGR2File(buffer) {
    const view = bufferView(buffer);
    const data = bufferBytes(buffer);
    const detect = detectGR2(view);
    if (!detect.ok) throw new Error("not a Granny2 file");
    const u32 = makeReader(view, detect.byteReversed);
    const h = MAGIC_SIZE;
    const version = u32(h);
    const totalSize = u32(h + 4);
    const crc = u32(h + 8);
    const sectionArrayOffset = u32(h + 12);
    const sectionCount = u32(h + 16);
    const rootType = (
      /** @type {[number, number]} */
      [u32(h + 20), u32(h + 24)]
    );
    const rootObject = (
      /** @type {[number, number]} */
      [u32(h + 28), u32(h + 32)]
    );
    const typeTag = u32(h + 36);
    const extraTags = new Array(EXTRA_TAG_COUNT);
    for (let i = 0; i < EXTRA_TAG_COUNT; i++) extraTags[i] = u32(h + 40 + i * 4);
    let stringDbCrc = 0;
    let reserved = [];
    if (version >= 7) {
      stringDbCrc = u32(h + 56);
      reserved = [u32(h + 60), u32(h + 64), u32(h + 68)];
    }
    const sections = new Array(sectionCount);
    const sectionsBase = MAGIC_SIZE + sectionArrayOffset;
    for (let index = 0; index < sectionCount; index++) {
      const off = sectionsBase + index * SECTION_RECORD_SIZE;
      sections[index] = {
        index,
        compression: u32(off),
        data_offset: u32(off + 4),
        data_size: u32(off + 8),
        expanded_size: u32(off + 12),
        internal_alignment: u32(off + 16),
        first_16bit: u32(off + 20),
        first_8bit: u32(off + 24),
        pointer_fixup_offset: u32(off + 28),
        pointer_fixup_count: u32(off + 32),
        mixed_marshalling_offset: u32(off + 36),
        mixed_marshalling_count: u32(off + 40),
        /** Computed : human name for {@link compression}. */
        get compression_name() {
          return COMPRESSION_NAMES[this.compression] ?? `unknown_${this.compression}`;
        },
        /** Computed : Granny semantic name for the slot at this {@link index}. */
        get semantic_name() {
          return SECTION_NAMES[this.index] ?? `section_${this.index}`;
        }
      };
    }
    const header = {
      version,
      total_size: totalSize,
      crc,
      section_array_offset: sectionArrayOffset,
      section_count: sectionCount,
      root_type: rootType,
      root_object: rootObject,
      type_tag: typeTag,
      extra_tags: extraTags,
      string_db_crc: stringDbCrc,
      reserved,
      pointer_size: detect.pointerSize,
      byte_reversed: detect.byteReversed
    };
    return (
      /** @type {GR2File} */
      {
        header,
        sections,
        data,
        /**
         * Slice of `data` carrying `section`'s on-disk compressed bytes.
         * @throws RangeError if the declared offset/size escape the buffer
         */
        sectionBytes(section) {
          const start = section.data_offset;
          const end = start + section.data_size;
          if (start < 0 || end > data.byteLength) {
            throw new RangeError(`section ${section.index} points outside file`);
          }
          return data.subarray(start, end);
        }
      }
    );
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/GrannyOodle0.js
  var OODLE0_HEADER_SIZE = 36;
  var OODLE0_BLOCK_COUNT = 3;
  var OFFSET_SPLIT_SHIFT = 2;
  var LOW_OFFSET_MASK = (1 << OFFSET_SPLIT_SHIFT) - 1;
  var MAX_LENS = 64;
  var LONG_LENGTHS = [MAX_LENS * 2, MAX_LENS * 3, MAX_LENS * 4, MAX_LENS * 8];
  var _OFFSET_BYTE_MASK = 511;
  var MASK31 = 2147483647;
  var OODLE0_MAX_EXPANDED_SIZE = 256 * 1024 * 1024;
  var OODLE0_MAX_EXPAND_RATIO = 1024;
  var OODLE0_MAX_ALPHABET = 1 << 21;
  var DecompressionError = class extends Error {
    constructor(message) {
      super(message);
      this.name = "DecompressionError";
    }
  };
  var Oodle0LZHeader = class {
    /**
     * @param {number} maxOffsetAndByte — raw u32 ; low 9 bits = max literal value, high 23 = max back-distance.
     * @param {number} uniqOffsetAndByte — raw u32 ; low 9 bits = literal alphabet size, high 23 = offset alphabet size.
     * @param {number} uniqLens — raw u32 ; 4 × u8 unique-symbol count, one per length-context group.
     */
    constructor(maxOffsetAndByte, uniqOffsetAndByte, uniqLens) {
      this.max_offset_and_byte = maxOffsetAndByte >>> 0;
      this.uniq_offset_and_byte = uniqOffsetAndByte >>> 0;
      this.uniq_lens = uniqLens >>> 0;
    }
    /** Max literal value the block emits — low 9 bits of `max_offset_and_byte`. */
    get max_byte_value() {
      return this.max_offset_and_byte & _OFFSET_BYTE_MASK;
    }
    /** Max LZ77 back-distance — high 23 bits of `max_offset_and_byte`. */
    get max_offset() {
      return this.max_offset_and_byte >>> 9;
    }
    /** Literal-alphabet size for the block's `bytes` arith model. */
    get unique_byte_values() {
      return this.uniq_offset_and_byte & _OFFSET_BYTE_MASK;
    }
    /** Offset-alphabet size for the block's `offset_high` arith model. */
    get unique_offsets() {
      return this.uniq_offset_and_byte >>> 9;
    }
    /**
     * Per-length-context unique-symbol count. The 65 length symbols
     * (`0..MAX_LENS`) split into 4 groups of 16 ; each group gets its
     * own arith-model sizing taken from one of the 4 bytes of `uniq_lens`
     * (MSB-first per group).
     *
     * @param {number} index — 0-based length symbol (`0..MAX_LENS`).
     * @returns {number} unique-symbol count for the containing group.
     */
    length_unique(index) {
      const group = Math.min(index / (MAX_LENS / 4) | 0, 3);
      return this.uniq_lens >>> (3 - group) * 8 & 255;
    }
  };
  function blockStops(section) {
    const expanded = section.expanded_size;
    const first16 = clampStop(section.first_16bit, expanded);
    let first8 = clampStop(section.first_8bit, expanded);
    if (first8 < first16) first8 = first16;
    return [0, first16, first8, expanded];
  }
  function clampStop(value, expandedSize) {
    if (value <= 0) return 0;
    if (value >= expandedSize) return expandedSize;
    return value;
  }
  function parseOodle0Plan(section, compressed) {
    if (compressed.length < OODLE0_HEADER_SIZE) {
      throw new RangeError(`oodle0 section ${section.index} too short for header`);
    }
    const view = new DataView(compressed.buffer, compressed.byteOffset, compressed.byteLength);
    const words = new Array(9);
    for (let i = 0; i < 9; i++) words[i] = view.getUint32(i * 4, true);
    const headers = [
      new Oodle0LZHeader(words[0], words[1], words[2]),
      new Oodle0LZHeader(words[3], words[4], words[5]),
      new Oodle0LZHeader(words[6], words[7], words[8])
    ];
    const stops = blockStops(section);
    const blocks = new Array(OODLE0_BLOCK_COUNT);
    for (let i = 0; i < OODLE0_BLOCK_COUNT; i++) {
      const start = stops[i];
      const end = stops[i + 1];
      blocks[i] = {
        index: i,
        output_start: start,
        output_end: end,
        output_size: Math.max(0, end - start),
        is_empty: end <= start,
        header: headers[i]
      };
    }
    return {
      section_index: section.index,
      expanded_size: section.expanded_size,
      blocks,
      bitstream_offset: OODLE0_HEADER_SIZE
    };
  }
  function u32lePadded(data, offset) {
    const cap = data.length;
    if (offset + 4 <= cap) {
      return (data[offset] | data[offset + 1] << 8 | data[offset + 2] << 16 | data[offset + 3] << 24) >>> 0;
    }
    let v = 0;
    if (offset < cap) v |= data[offset];
    if (offset + 1 < cap) v |= data[offset + 1] << 8;
    if (offset + 2 < cap) v |= data[offset + 2] << 16;
    if (offset + 3 < cap) v |= data[offset + 3] << 24;
    return v >>> 0;
  }
  function bitReverse(value, nbits) {
    let result = 0;
    for (let i = 0; i < nbits; i++) {
      result = result << 1 | value >>> i & 1;
    }
    return result >>> 0;
  }
  var VarBits = class {
    constructor(data, offset) {
      this.data = data;
      this.cur = offset;
      this.bits = 0;
      this.bitlen = 0;
    }
    /** Consume `nbits` bits ; return them as an unsigned int (`0..2^nbits - 1`). */
    get(nbits) {
      if (nbits === 0) return 0;
      const mask = (1 << nbits >>> 0) - 1;
      if (this.bitlen >= nbits) {
        const value2 = this.bits & mask;
        this.bits = this.bits >>> nbits;
        this.bitlen -= nbits;
        return value2;
      }
      const word = u32lePadded(this.data, this.cur);
      this.cur += 4;
      const need = nbits - this.bitlen;
      const lowMask = (1 << need >>> 0) - 1;
      const wordLow = word & lowMask;
      const value = (this.bits | wordLow << this.bitlen) >>> 0;
      this.bits = word >>> need;
      this.bitlen = this.bitlen + 32 - nbits;
      return value;
    }
    /** Consume exactly 1 bit (`0` or `1`). Fast path for the inner decode loop. */
    get1() {
      if (this.bitlen) {
        const value = this.bits & 1;
        this.bits = this.bits >>> 1;
        this.bitlen -= 1;
        return value;
      }
      const word = u32lePadded(this.data, this.cur);
      this.cur += 4;
      this.bits = word >>> 1;
      this.bitlen = 31;
      return word & 1;
    }
  };
  var ArithBits = class {
    constructor(data, offset) {
      this.vbits = new VarBits(data, offset);
      this.high = MASK31;
      this.low = 0;
      this.code = bitReverse(this.vbits.get(31), 31);
    }
    /** Compute the cumulative count `c` such that the current code falls in `[start, start+c]` for a given `scale`. */
    getCount(scale) {
      if (scale <= 0) return 0;
      const width = this.high - this.low + 1;
      return Math.floor(((this.code - this.low + 1) * scale - 1) / width);
    }
    /** Decode an integer value in `[0, scale)` directly (used for escape symbols). */
    getValue(scale) {
      let value = this.getCount(scale);
      if (value >= scale) value = scale - 1;
      this.remove(value, 1, scale);
      return value;
    }
    /**
     * Advance the decoder by removing the `[start, start+count)` interval
     * from the current `[low, high]` range. Performs the standard arith-
     * coding renormalization (8-bit + 4-bit + 1-bit unscaled rounds, then
     * the underflow loop) — see RAD's leaked source for asm-cite parity.
     */
    remove(start, count, scale) {
      if (scale <= 0) return;
      let high = this.high;
      let low = this.low;
      let code = this.code;
      const width = high - low + 1;
      high = low + Math.floor(width * (start + count) / scale) - 1 >>> 0;
      low = low + Math.floor(width * start / scale) >>> 0;
      if (((high ^ low) & 1073741824) === 0) {
        while (((high ^ low) & 2139095040) === 0) {
          low = low << 8 >>> 0;
          high = (high << 8 | 255) >>> 0;
          const byte = this.vbits.get(8);
          code = (code << 8 | bitReverse(byte & 15, 4) << 4 | bitReverse(byte >>> 4, 4)) >>> 0;
        }
        if (((high ^ low) & 2013265920) === 0) {
          low = low << 4 >>> 0;
          high = (high << 4 | 15) >>> 0;
          code = (code << 4 | bitReverse(this.vbits.get(4), 4)) >>> 0;
        }
        while (((high ^ low) & 1073741824) === 0) {
          low = low << 1 >>> 0;
          high = (high << 1 | 1) >>> 0;
          code = (code << 1 | this.vbits.get1()) >>> 0;
        }
      }
      while (low & 536870912 && !(high & 536870912)) {
        code = (code ^ 536870912) >>> 0;
        low = (low & 536870911) << 1 >>> 0;
        high = (high << 1 | 1073741825) >>> 0;
        code = (code << 1 | this.vbits.get1()) >>> 0;
      }
      this.high = high & MASK31;
      this.low = low & MASK31;
      this.code = code & MASK31;
    }
  };
  function alignedCount(uniqueValues) {
    return uniqueValues + 5 & ~3;
  }
  function bestShift(value) {
    if (value < 6) return [0, 15, 0];
    let bestMax = 4294967295;
    let bestBin = 0;
    for (let index = 0; index < 16; index++) {
      const size = 1 << index;
      const bins = Math.min(Math.floor((value + size - 1) / size), 16);
      let last = value - size * (bins - 1);
      if (last < size) last = size;
      if (last < bestMax) {
        bestBin = index;
        bestMax = last;
      }
      if (size > value) break;
    }
    const binSize = 1 << bestBin;
    return [binSize, bestBin, 15 * binSize];
  }
  var EscapeSymbol = class {
    constructor(index) {
      this.index = index;
    }
  };
  var ArithModel = class {
    constructor(uniqueValues) {
      if (uniqueValues > OODLE0_MAX_ALPHABET) {
        throw new DecompressionError(
          `oodle0 arith alphabet ${uniqueValues} exceeds cap ${OODLE0_MAX_ALPHABET}`
        );
      }
      this.unique_values = uniqueValues;
      const count = alignedCount(uniqueValues);
      this.totals = new Array(16).fill(0);
      this.counts = new Array(count).fill(0);
      this.values = new Array(count).fill(0);
      this.number = 0;
      const [binSize, binShift, lastBinStart] = bestShift(uniqueValues + 1);
      this.bin_size = binSize;
      this.bin_shift = binShift;
      this.last_bin_start = lastBinStart;
      this._quickIncrement(0, 3);
    }
    /**
     * Decode one symbol from `bits`. Returns the symbol value as a plain
     * number, or an {@link EscapeSymbol} marker when a new alphabet
     * entry is being introduced.
     *
     * @throws DecompressionError if the model overflows its capacity
     */
    decompress(bits) {
      if (this.totals[15] >= 16384) this._rescale();
      const scale = this.totals[15];
      const count = bits.getCount(scale);
      const [pos, start] = this._findPos(count);
      const oldCount = this.counts[pos];
      this._incrementTotals(pos, 1);
      bits.remove(start, oldCount, this.totals[15] - 1);
      this.counts[pos] = this.counts[pos] + 1 & 65535;
      if (pos === 0) {
        this.number += 1;
        if (this.number >= this.counts.length) {
          throw new DecompressionError("oodle0 escape exceeded model capacity");
        }
        this._quickIncrement(this.number, 2);
        if (this.number === this.unique_values) {
          this._decrementCounts(0, this.counts[0]);
        }
        return new EscapeSymbol(this.number);
      }
      return this.values[pos];
    }
    /** Register the value behind an escape marker so subsequent reads find it. */
    setEscaped(marker, value) {
      this.values[marker.index] = value & 65535;
    }
    /**
     * Find the position whose cumulative count contains `count`.
     *
     * Two-stage : first a 4-compare binary search over the 16-entry
     * cumulative `totals` to find the right bin, then a bounded linear
     * scan within that bin's `counts` slice. The bin layout is what
     * {@link bestShift} was designed for — bin sizes are picked so the
     * within-bin scan stays small.
     */
    _findPos(count) {
      const totals = this.totals;
      let lo = 0;
      let hi = 16;
      while (lo < hi) {
        const mid = lo + hi >>> 1;
        if (count < totals[mid]) hi = mid;
        else lo = mid + 1;
      }
      const bin = lo;
      const counts = this.counts;
      const binShift = this.bin_shift;
      let pos;
      let end;
      if (bin < 15) {
        pos = bin << binShift;
        end = pos + (1 << binShift);
        if (end > counts.length) end = counts.length;
      } else {
        pos = this.last_bin_start;
        end = counts.length;
      }
      let start = bin > 0 ? totals[bin - 1] : 0;
      while (pos < end) {
        const entry = counts[pos];
        if (count < start + entry) return [pos, start];
        start += entry;
        pos++;
      }
      throw new DecompressionError(`oodle0 model count ${count} outside total ${start}`);
    }
    /**
     * Increment `counts[value]` AND `totals[bin(value)..15]` by `delta`.
     *
     * The original RAD code packed two parallel u16 increments into a
     * single u32 add ; in our codepaths the packed amount always had
     * identical hi and lo halves (0x10001, 0x20002, 0x30003), so a
     * straight per-bin u16 add gives the same result without the
     * packing dance. {@link _decrementCounts} handles the asymmetric
     * negative-pair case directly.
     */
    _quickIncrement(value, delta) {
      this._incrementTotals(value, delta);
      this.counts[value] = this.counts[value] + delta & 65535;
    }
    /** Add `delta` (u16) to `totals[bin(value)..15]` cumulatively. */
    _incrementTotals(value, delta) {
      const totals = this.totals;
      if (value >= this.last_bin_start) {
        totals[15] = totals[15] + delta & 65535;
        return;
      }
      for (let i = value >>> this.bin_shift; i < 16; i++) {
        totals[i] = totals[i] + delta & 65535;
      }
    }
    /** Decrement `counts[value]` AND `totals[bin(value)..15]` by `amount`. */
    _decrementCounts(value, amount) {
      const totals = this.totals;
      this.counts[value] = this.counts[value] - amount & 65535;
      if (value >= this.last_bin_start) {
        totals[15] = totals[15] - amount & 65535;
        return;
      }
      for (let i = value >>> this.bin_shift; i < 16; i++) {
        totals[i] = totals[i] - amount & 65535;
      }
    }
    /**
     * Halve every `counts` entry and rebuild `totals`. Triggered when the
     * cumulative tally hits 16384. Also drops entries that fall to ≤ 1
     * and re-bins the survivors based on the updated alphabet size.
     */
    _rescale() {
      const [binSize, binShift, lastBinStart] = bestShift(this.number + 1);
      this.bin_size = binSize;
      this.bin_shift = binShift;
      this.last_bin_start = lastBinStart;
      const bins = new Array(16).fill(0);
      this.counts[0] = this.counts[0] >>> 1;
      bins[0 < this.last_bin_start ? 0 : 15] += this.counts[0];
      let maxCount = 0;
      let maxPos = 0;
      let index = 1;
      let done = false;
      while (index <= this.number && !done) {
        while (this.counts[index] <= 1) {
          if (index < this.number) {
            this.counts[index] = this.counts[this.number];
            this.values[index] = this.values[this.number];
            this.counts[this.number] = 0;
            this.number -= 1;
          } else {
            this.counts[index] = 0;
            this.number -= 1;
            done = true;
            break;
          }
        }
        if (done) break;
        this.counts[index] = this.counts[index] >>> 1;
        if (this.counts[index] > maxCount) {
          maxCount = this.counts[index];
          maxPos = index;
        }
        const bucket = index < this.last_bin_start ? index >>> this.bin_shift : 15;
        bins[bucket] += this.counts[index];
        index += 1;
      }
      if (maxCount) {
        let swapPos;
        if (this.number < this.last_bin_start) {
          swapPos = this.number >>> this.bin_shift << this.bin_shift;
        } else {
          swapPos = this.last_bin_start;
        }
        if (swapPos === 0) swapPos = 1;
        if (maxPos !== swapPos) {
          const oldCount = this.counts[swapPos];
          this.counts[swapPos] = this.counts[maxPos];
          const swapBucket = swapPos < this.last_bin_start ? swapPos >>> this.bin_shift : 15;
          const maxBucket = maxPos < this.last_bin_start ? maxPos >>> this.bin_shift : 15;
          bins[swapBucket] += -oldCount + this.counts[swapPos];
          bins[maxBucket] += oldCount - this.counts[swapPos];
          this.counts[maxPos] = oldCount;
          const tmp = this.values[swapPos];
          this.values[swapPos] = this.values[maxPos];
          this.values[maxPos] = tmp;
        }
      }
      if (this.number !== this.unique_values && this.counts[0] === 0) {
        this.counts[0] = this.counts[0] + 2 & 65535;
        bins[0 < this.last_bin_start ? 0 : 15] += 2;
      }
      let running = 0;
      for (let i = 0; i < 16; i++) {
        running += bins[i];
        this.totals[i] = running & 65535;
      }
    }
  };
  var LZState = class {
    constructor(header) {
      this.max_bytes = header.max_byte_value;
      this.max_offsets = header.max_offset;
      this.max_offset_low = Math.min(this.max_offsets, LOW_OFFSET_MASK + 1);
      this.bytes = new ArithModel(header.unique_byte_values);
      const lengths = new Array(MAX_LENS + 1);
      for (let i = 0; i <= MAX_LENS; i++) lengths[i] = new ArithModel(header.length_unique(i));
      this.lengths = lengths;
      this.offset_low = new ArithModel(this.max_offset_low);
      this.offset_high = new ArithModel(header.unique_offsets);
      this.bytes_decompressed = 0;
      this.last_length = 0;
    }
  };
  function readModelSymbol(model, bits, escapeScale) {
    const value = model.decompress(bits);
    if (value instanceof EscapeSymbol) {
      const escaped = bits.getValue(escapeScale);
      model.setEscaped(value, escaped);
      return escaped;
    }
    return value | 0;
  }
  function decompressOodle0(section, compressed) {
    if (section.expanded_size === 0) return new Uint8Array(0);
    if (compressed.length < OODLE0_HEADER_SIZE) {
      throw new DecompressionError("oodle0 data too short for 3 block headers");
    }
    const expanded = section.expanded_size;
    if (expanded > OODLE0_MAX_EXPANDED_SIZE || expanded > compressed.length * OODLE0_MAX_EXPAND_RATIO) {
      throw new DecompressionError(
        `oodle0 expanded_size ${expanded} exceeds cap (${OODLE0_MAX_EXPANDED_SIZE} B / ${OODLE0_MAX_EXPAND_RATIO}\xD7 of ${compressed.length} B)`
      );
    }
    const plan = parseOodle0Plan(section, compressed);
    const bits = new ArithBits(compressed, OODLE0_HEADER_SIZE);
    const output = new Uint8Array(section.expanded_size);
    let cursor = 0;
    for (let i = 0; i < OODLE0_BLOCK_COUNT; i++) {
      const block = plan.blocks[i];
      if (block.is_empty) continue;
      const state = new LZState(block.header);
      cursor = decodeBlock(state, bits, output, cursor, block.output_end);
    }
    if (cursor !== section.expanded_size) {
      throw new DecompressionError(`oodle0 decompressed ${cursor}, expected ${section.expanded_size}`);
    }
    return output;
  }
  function decodeBlock(state, bits, output, cursor, stop) {
    while (cursor < stop) {
      const previousLength = state.last_length;
      const lengthSymbol = readModelSymbol(state.lengths[previousLength], bits, MAX_LENS + 1);
      state.last_length = lengthSymbol;
      if (lengthSymbol) {
        const length = lengthSymbol >= MAX_LENS - 3 ? LONG_LENGTHS[lengthSymbol - (MAX_LENS - 3)] : lengthSymbol + 1;
        const low = readModelSymbol(state.offset_low, bits, state.max_offset_low);
        const highScale = (Math.min(state.max_offsets, state.bytes_decompressed) >>> OFFSET_SPLIT_SHIFT) + 1;
        const high = readModelSymbol(state.offset_high, bits, highScale);
        const distance = low + 1 + (high << OFFSET_SPLIT_SHIFT);
        if (distance <= 0 || distance > cursor) {
          throw new DecompressionError(`oodle0 invalid copy distance ${distance}`);
        }
        const src = cursor - distance;
        for (let k = 0; k < length; k++) {
          output[cursor + k] = output[src + k];
        }
        cursor += length;
        state.bytes_decompressed += length;
      } else {
        const literal = readModelSymbol(state.bytes, bits, state.max_bytes);
        if (literal < 0 || literal > 255) {
          throw new DecompressionError(`oodle0 invalid literal ${literal}`);
        }
        output[cursor++] = literal;
        state.bytes_decompressed += 1;
      }
    }
    return cursor;
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/GrannyTransform.js
  var IDENTITY_TRANSFORM = Object.freeze({
    flags: 0,
    position: [0, 0, 0],
    orientation: [0, 0, 0, 1],
    scaleShear: [1, 0, 0, 0, 1, 0, 0, 0, 1]
  });
  function readTransform(loaded, section, offset) {
    const data = loaded.sectionsOriginal[section];
    if (!data || offset < 0 || offset + 68 > data.length) return IDENTITY_TRANSFORM;
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    const flags = view.getUint32(offset, true);
    const values = new Array(16);
    for (let i = 0; i < 16; i++) {
      values[i] = view.getFloat32(offset + 4 + i * 4, true);
    }
    return {
      flags,
      position: [values[0], values[1], values[2]],
      orientation: [values[3], values[4], values[5], values[6]],
      scaleShear: [
        values[7],
        values[8],
        values[9],
        values[10],
        values[11],
        values[12],
        values[13],
        values[14],
        values[15]
      ]
    };
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/GrannyTypeTree.js
  var GrannyParseError = class extends Error {
    constructor(message) {
      super(message);
      this.name = "GrannyParseError";
    }
  };
  function decompressOne(section, compressed) {
    if (section.expanded_size === 0) return new Uint8Array(0);
    if (section.compression === COMPRESSION_NONE) {
      if (compressed.length < section.expanded_size) {
        throw new RangeError(
          `section ${section.index} short: ${compressed.length} < ${section.expanded_size}`
        );
      }
      return compressed.subarray(0, section.expanded_size);
    }
    if (section.compression === COMPRESSION_OODLE0) {
      return decompressOodle0(section, compressed);
    }
    throw new Error(`unsupported compression ${section.compression}`);
  }
  var MT_END = 0;
  var MT_INLINE = 1;
  var MT_REFERENCE = 2;
  var MT_REFERENCE_TO_ARRAY = 3;
  var MT_ARRAY_OF_REFERENCES = 4;
  var MT_VARIANT_REFERENCE = 5;
  var MT_REFERENCE_TO_VARIANT_ARRAY = 7;
  var MT_STRING = 8;
  var MT_TRANSFORM = 9;
  var MT_REAL32 = 10;
  var MT_INT8 = 11;
  var MT_UINT8 = 12;
  var MT_BINORMAL_INT8 = 13;
  var MT_NORMAL_UINT8 = 14;
  var MT_INT16 = 15;
  var MT_UINT16 = 16;
  var MT_BINORMAL_INT16 = 17;
  var MT_NORMAL_UINT16 = 18;
  var MT_INT32 = 19;
  var MT_UINT32 = 20;
  var MT_EMPTY_REFERENCE = 22;
  var MEMBER_TYPE_NAMES = {
    0: "end",
    1: "inline",
    2: "reference",
    3: "reference_to_array",
    4: "array_of_references",
    5: "variant_reference",
    6: "unsupported",
    7: "reference_to_variant_array",
    8: "string",
    9: "transform",
    10: "real32",
    11: "int8",
    12: "uint8",
    13: "binormal_int8",
    14: "normal_uint8",
    15: "int16",
    16: "uint16",
    17: "binormal_int16",
    18: "normal_uint16",
    19: "int32",
    20: "uint32",
    21: "real16",
    22: "empty_reference"
  };
  var SCALAR_SIZES = {
    10: 4,
    // real32
    11: 1,
    // int8
    12: 1,
    // uint8
    13: 1,
    // binormal_int8
    14: 1,
    // normal_uint8
    15: 2,
    // int16
    16: 2,
    // uint16
    17: 2,
    // binormal_int16
    18: 2,
    // normal_uint16
    19: 4,
    // int32
    20: 4,
    // uint32
    21: 2
    // real16
  };
  var FAKE_POINTER_BASE = 268435456;
  var FAKE_SECTION_STRIDE = 1048576;
  function makeFakePointer(section, offset) {
    return FAKE_POINTER_BASE + section * FAKE_SECTION_STRIDE + offset >>> 0;
  }
  function decodeFakePointer(pointer, sectionCount) {
    if (pointer < FAKE_POINTER_BASE) return null;
    const value = pointer - FAKE_POINTER_BASE >>> 0;
    const section = value / FAKE_SECTION_STRIDE | 0;
    const offset = value - section * FAKE_SECTION_STRIDE;
    if (section < 0 || section >= sectionCount) return null;
    return [section, offset];
  }
  function pointerSizeBytes(file) {
    return file.header.pointer_size >>> 3;
  }
  function makeU32Reader(byteReversed) {
    const little = !byteReversed;
    return (bytes, offset) => {
      if (offset < 0 || offset + 4 > bytes.length) {
        throw new RangeError(
          `gr2 type-tree read out of range at 0x${offset.toString(16)} (cap 0x${bytes.length.toString(16)})`
        );
      }
      const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      return view.getUint32(offset, little);
    };
  }
  function readPointer(bytes, offset, pointerSize, byteReversed) {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const little = !byteReversed;
    if (pointerSize === 4) return view.getUint32(offset, little);
    const lo = view.getUint32(offset, little) >>> 0;
    const hi = view.getUint32(offset + 4, little) >>> 0;
    return hi * 4294967296 + lo;
  }
  function writePointer(bytes, offset, value, pointerSize, byteReversed) {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const little = !byteReversed;
    if (pointerSize === 4) {
      view.setUint32(offset, value >>> 0, little);
      return;
    }
    const lo = value >>> 0;
    const hi = Math.floor(value / 4294967296) >>> 0;
    view.setUint32(offset, lo, little);
    view.setUint32(offset + 4, hi, little);
  }
  function loadGR2(file) {
    const sections = file.sections;
    const sectionCount = sections.length;
    const sectionsOriginal = new Array(sectionCount);
    const sectionsFixed = new Array(sectionCount);
    for (let i = 0; i < sectionCount; i++) {
      const section = sections[i];
      const compressed = file.sectionBytes(section);
      const expanded = decompressOne(section, compressed);
      sectionsOriginal[i] = expanded;
      sectionsFixed[i] = new Uint8Array(expanded);
    }
    const pointerSize = pointerSizeBytes(file);
    if (pointerSize !== 4 && pointerSize !== 8) {
      throw new Error(`unsupported pointer size ${file.header.pointer_size}`);
    }
    const pointerFixups = readPointerFixups(file);
    const mixedFixups = readMixedMarshallingFixups(file);
    if (file.header.byte_reversed && mixedFixups.length > 0) {
      throw new Error(
        "cross-endian asset (byte_reversed + mixed-marshalling table) is not supported \u2014 iRO corpus is all little-endian"
      );
    }
    for (let i = 0; i < pointerFixups.length; i++) {
      const fixup = pointerFixups[i];
      if (fixup.source_section >= sectionCount) continue;
      const data = sectionsFixed[fixup.source_section];
      if (fixup.source_offset + pointerSize > data.length) continue;
      const fake = makeFakePointer(fixup.target[0], fixup.target[1]);
      writePointer(data, fixup.source_offset, fake, pointerSize, file.header.byte_reversed);
    }
    return {
      file,
      sectionsOriginal,
      sectionsFixed,
      pointerFixups,
      mixedFixups,
      pointerSize
    };
  }
  function readPointerFixups(file) {
    const u32 = makeU32Reader(file.header.byte_reversed);
    const data = file.data;
    const sections = file.sections;
    const fixups = [];
    for (let s = 0; s < sections.length; s++) {
      const section = sections[s];
      const count = section.pointer_fixup_count;
      const offset = section.pointer_fixup_offset;
      if (count === 0 || offset === 0) continue;
      const entrySize = 12;
      if (offset + count * entrySize > data.length) {
        throw new RangeError(
          `section ${s} pointer fixup table at 0x${offset.toString(16)} (${count} entries) escapes file (size 0x${data.length.toString(16)})`
        );
      }
      for (let i = 0; i < count; i++) {
        const base = offset + i * entrySize;
        fixups.push({
          source_section: s,
          source_offset: u32(data, base),
          target: (
            /** @type {SectionRef} */
            [u32(data, base + 4), u32(data, base + 8)]
          )
        });
      }
    }
    return fixups;
  }
  function readMixedMarshallingFixups(file) {
    const u32 = makeU32Reader(file.header.byte_reversed);
    const data = file.data;
    const sections = file.sections;
    const fixups = [];
    for (let s = 0; s < sections.length; s++) {
      const section = sections[s];
      const count = section.mixed_marshalling_count;
      const offset = section.mixed_marshalling_offset;
      if (count === 0 || offset === 0) continue;
      const entrySize = 16;
      if (offset + count * entrySize > data.length) {
        throw new RangeError(
          `section ${s} mixed-marshalling table at 0x${offset.toString(16)} (${count} entries) escapes file (size 0x${data.length.toString(16)})`
        );
      }
      for (let i = 0; i < count; i++) {
        const base = offset + i * entrySize;
        fixups.push({
          source_section: s,
          count: u32(data, base),
          offset: u32(data, base + 4),
          type_ref: (
            /** @type {SectionRef} */
            [u32(data, base + 8), u32(data, base + 12)]
          )
        });
      }
    }
    return fixups;
  }
  function looksText(bytes) {
    const len = bytes.length;
    if (len === 0) return false;
    for (let i = 0; i < len; i++) {
      const v = bytes[i];
      if (v === 9 || v === 10 || v === 13) continue;
      if (v < 32 || v === 127) return false;
    }
    return true;
  }
  var TEXT_DECODER = new TextDecoder("utf-8", { fatal: false });
  function readGrannyString(loaded, ref, maxLength = 1024) {
    const section = ref[0];
    const offset = ref[1];
    if (section >= loaded.sectionsOriginal.length) return "";
    const data = loaded.sectionsOriginal[section];
    if (offset < 0 || offset >= data.length) return "";
    if (offset + 4 <= data.length) {
      const u32 = makeU32Reader(loaded.file.header.byte_reversed);
      const length = u32(data, offset);
      const end2 = offset + 4 + length;
      if (length > 0 && length <= maxLength && end2 <= data.length) {
        const slice2 = data.subarray(offset + 4, end2);
        if (looksText(slice2)) {
          return TEXT_DECODER.decode(slice2).replace(/\0+$/, "");
        }
      }
    }
    const cap = Math.min(data.length, offset + maxLength);
    let end = cap;
    for (let i = offset; i < cap; i++) {
      if (data[i] === 0) {
        end = i;
        break;
      }
    }
    const slice = data.subarray(offset, end);
    if (!looksText(slice)) return "";
    return TEXT_DECODER.decode(slice);
  }
  function readStringPointer(loaded, pointer) {
    const ref = decodeFakePointer(pointer, loaded.sectionsOriginal.length);
    if (ref === null) return "";
    return readGrannyString(loaded, ref);
  }
  function parseTypeTree(loaded, ref, options = {}) {
    const maxMembers = options.maxMembers ?? 512;
    const section = ref[0];
    const startOffset = ref[1];
    if (section >= loaded.sectionsFixed.length) return [];
    const data = loaded.sectionsFixed[section];
    const u32 = makeU32Reader(loaded.file.header.byte_reversed);
    const sectionCount = loaded.sectionsFixed.length;
    const entries = [];
    let offset = startOffset;
    for (let i = 0; i < maxMembers; i++) {
      if (offset + 32 > data.length) break;
      const memberType = u32(data, offset);
      if (memberType === MT_END) break;
      const namePtr = u32(data, offset + 4);
      const typePtr = u32(data, offset + 8);
      const arrayWidth = u32(data, offset + 12);
      const extra0 = u32(data, offset + 16);
      const extra1 = u32(data, offset + 20);
      const extra2 = u32(data, offset + 24);
      const name = readStringPointer(loaded, namePtr) || `member_${entries.length}`;
      const referenceType = decodeFakePointer(typePtr, sectionCount);
      entries.push({
        memberType,
        memberTypeName: MEMBER_TYPE_NAMES[memberType] ?? `type_${memberType}`,
        name,
        referenceType,
        arrayWidth: arrayWidth || 1,
        extra: (
          /** @type {[number, number, number]} */
          [extra0, extra1, extra2]
        ),
        offset
      });
      offset += 32;
    }
    return entries;
  }
  function memberStorageSize(member, pointerSize) {
    const width = member.arrayWidth || 1;
    const t = member.memberType;
    const scalar = SCALAR_SIZES[t];
    if (scalar !== void 0) return scalar * width;
    if (t === MT_REFERENCE || t === MT_EMPTY_REFERENCE || t === MT_STRING) {
      return pointerSize;
    }
    if (t === MT_REFERENCE_TO_ARRAY || t === MT_ARRAY_OF_REFERENCES) {
      return 4 + pointerSize;
    }
    if (t === MT_VARIANT_REFERENCE) return pointerSize * 2;
    if (t === MT_REFERENCE_TO_VARIANT_ARRAY) return pointerSize + 4 + pointerSize;
    if (t === MT_TRANSFORM) return 68;
    if (t === MT_INLINE) return 0;
    return pointerSize;
  }
  function objectStorageSize(loaded, members, pointerSize, seen, memo = {}) {
    let size = 0;
    for (let i = 0; i < members.length; i++) {
      const member = members[i];
      if (member.memberType === MT_INLINE && member.referenceType) {
        const key = member.referenceType[0] * FAKE_SECTION_STRIDE + member.referenceType[1];
        if (seen.has(key)) continue;
        if (memo[key] !== void 0) {
          size += memo[key];
          continue;
        }
        const childSeen = new Set(seen);
        childSeen.add(key);
        const sub = parseTypeTree(loaded, member.referenceType);
        const subSize = objectStorageSize(loaded, sub, pointerSize, childSeen, memo);
        memo[key] = subSize;
        size += subSize;
      } else {
        size += memberStorageSize(member, pointerSize);
      }
    }
    return size;
  }
  var MAX_INLINE_DEPTH = 64;
  function parseObject(loaded, typeTree, ref, options = {}, depth = 0, seen = null) {
    const maxArrayRefs = options.maxArrayRefs ?? 256;
    const pointerSize = loaded.pointerSize;
    const byteReversed = loaded.file.header.byte_reversed;
    const section = ref[0];
    const startOffset = ref[1];
    if (section >= loaded.sectionsFixed.length) return (
      /** @type {ParsedObject} */
      {}
    );
    const fixed = loaded.sectionsFixed[section];
    const raw = loaded.sectionsOriginal[section];
    const sectionCount = loaded.sectionsFixed.length;
    const u32 = makeU32Reader(byteReversed);
    const rawView = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
    const little = !byteReversed;
    const out = (
      /** @type {Record<string, ParsedField>} */
      {}
    );
    let offset = startOffset;
    for (let i = 0; i < typeTree.length; i++) {
      const member = typeTree[i];
      const size = memberStorageSize(member, pointerSize);
      if (offset + size > fixed.length) break;
      const field = {
        type: member.memberTypeName,
        offset
      };
      if (member.referenceType) {
        field.reference_type = { section: member.referenceType[0], offset: member.referenceType[1] };
      }
      const t = member.memberType;
      if (t === MT_REFERENCE || t === MT_EMPTY_REFERENCE) {
        const pointer = readPointer(fixed, offset, pointerSize, byteReversed);
        field.target = refDict(decodeFakePointer(pointer, sectionCount));
      } else if (t === MT_STRING) {
        const pointer = readPointer(fixed, offset, pointerSize, byteReversed);
        field.value = readStringPointer(loaded, pointer);
        field.target = refDict(decodeFakePointer(pointer, sectionCount));
      } else if (t === MT_REFERENCE_TO_ARRAY || t === MT_ARRAY_OF_REFERENCES) {
        const count = u32(raw, offset);
        const pointer = readPointer(fixed, offset + 4, pointerSize, byteReversed);
        const target = decodeFakePointer(pointer, sectionCount);
        field.count = count;
        field.target = refDict(target);
        field.truncated = count > maxArrayRefs;
        if (t === MT_ARRAY_OF_REFERENCES) {
          field.element_refs = readArrayReferences(loaded, target, count, maxArrayRefs);
        }
      } else if (t === MT_REFERENCE_TO_VARIANT_ARRAY) {
        const typePointer = readPointer(fixed, offset, pointerSize, byteReversed);
        const count = u32(raw, offset + pointerSize);
        const objectPointer = readPointer(fixed, offset + pointerSize + 4, pointerSize, byteReversed);
        field.variant_type = refDict(decodeFakePointer(typePointer, sectionCount));
        field.count = count;
        field.target = refDict(decodeFakePointer(objectPointer, sectionCount));
        field.truncated = count > maxArrayRefs;
      } else if (t === MT_VARIANT_REFERENCE) {
        const typePointer = readPointer(fixed, offset, pointerSize, byteReversed);
        const objectPointer = readPointer(fixed, offset + pointerSize, pointerSize, byteReversed);
        field.variant_type = refDict(decodeFakePointer(typePointer, sectionCount));
        field.target = refDict(decodeFakePointer(objectPointer, sectionCount));
      } else if (t === MT_INT32) {
        field.value = rawView.getInt32(offset, little);
      } else if (t === MT_UINT32) {
        field.value = rawView.getUint32(offset, little);
      } else if (t === MT_INT16) {
        field.value = rawView.getInt16(offset, little);
      } else if (t === MT_UINT16) {
        field.value = rawView.getUint16(offset, little);
      } else if (t === MT_INT8) {
        field.value = rawView.getInt8(offset);
      } else if (t === MT_UINT8) {
        field.value = rawView.getUint8(offset);
      } else if (t === MT_REAL32) {
        field.value = rawView.getFloat32(offset, little);
      } else if (t === MT_TRANSFORM) {
        field.value = readTransform(loaded, section, offset);
      } else if (t === MT_INLINE && member.referenceType) {
        const key = member.referenceType[0] * FAKE_SECTION_STRIDE + member.referenceType[1];
        if (depth >= MAX_INLINE_DEPTH) {
          throw new GrannyParseError(
            `inline nesting exceeds MAX_INLINE_DEPTH (${MAX_INLINE_DEPTH}) at section ${section} offset 0x${offset.toString(16)}`
          );
        }
        if (seen !== null && seen.has(key)) {
          throw new GrannyParseError(
            `self-referential inline type [${member.referenceType[0]}, ${member.referenceType[1]}] at section ${section} offset 0x${offset.toString(16)}`
          );
        }
        const childSeen = seen !== null ? new Set(seen) : /* @__PURE__ */ new Set();
        childSeen.add(key);
        const subTree = parseTypeTree(loaded, member.referenceType);
        const subRef = (
          /** @type {SectionRef} */
          [section, offset]
        );
        field.inline = parseObject(loaded, subTree, subRef, options, depth + 1, childSeen);
        const subSize = objectStorageSize(loaded, subTree, pointerSize, /* @__PURE__ */ new Set());
        offset += subSize;
        out[member.name] = field;
        continue;
      }
      out[member.name] = field;
      offset += size;
    }
    return out;
  }
  function readArrayReferences(loaded, arrayRef, count, maxCount) {
    if (arrayRef === null || count <= 0) return [];
    const pointerSize = loaded.pointerSize;
    const byteReversed = loaded.file.header.byte_reversed;
    const data = loaded.sectionsFixed[arrayRef[0]];
    if (!data) return [];
    const sectionCount = loaded.sectionsFixed.length;
    const limit = count < maxCount ? count : maxCount;
    const refs = new Array(limit);
    let n = 0;
    for (let i = 0; i < limit; i++) {
      const off = arrayRef[1] + i * pointerSize;
      if (off + pointerSize > data.length) break;
      const pointer = readPointer(data, off, pointerSize, byteReversed);
      const decoded = decodeFakePointer(pointer, sectionCount);
      if (decoded === null) continue;
      refs[n++] = { section: decoded[0], offset: decoded[1] };
    }
    refs.length = n;
    return refs;
  }
  function readReferenceArrayObjects(loaded, arrayRef, count, typeRef, options = {}) {
    if (arrayRef === null || typeRef === null || count <= 0) return [];
    const maxCount = options.maxCount ?? 64;
    const maxArrayRefs = options.maxArrayRefs ?? maxCount;
    const typeMembers = parseTypeTree(loaded, [typeRef.section, typeRef.offset]);
    const stride = objectStorageSize(loaded, typeMembers, loaded.pointerSize, /* @__PURE__ */ new Set());
    if (stride <= 0) return [];
    const limit = count < maxCount ? count : maxCount;
    const out = new Array(limit);
    const parseOpts = { maxArrayRefs };
    for (let i = 0; i < limit; i++) {
      const offset = arrayRef.offset + i * stride;
      const ref = { section: arrayRef.section, offset };
      const fields = parseObject(loaded, typeMembers, [arrayRef.section, offset], parseOpts);
      out[i] = { ref, fields };
    }
    return out;
  }
  function refDict(ref) {
    if (ref === null) return null;
    return { section: ref[0], offset: ref[1] };
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/GrannyMesh.js
  function extractMeshes(loaded, options = {}) {
    const maxMeshes = options.maxMeshes ?? 32;
    const maxMaterials = options.maxMaterials ?? 4096;
    const maxBones = options.maxBones ?? 4096;
    const meshSummaries = summarizeMeshes(loaded, maxMeshes);
    if (meshSummaries.length === 0) return [];
    const materialsByRef = materialMap(loaded, maxMaterials);
    const meshes = [];
    const summaryCount = meshSummaries.length;
    for (let i = 0; i < summaryCount; i++) {
      const summary = meshSummaries[i];
      const vertexData = summary.primaryVertexData;
      const topology = summary.primaryTopology;
      if (!vertexData) continue;
      const vertices = vertexData.Vertices;
      if (!vertices) continue;
      const vertexRef = vertices.target ?? null;
      const vertexTypeRef = vertices.variant_type ?? null;
      const vertexCount = vertices.count ?? 0;
      if (!vertexRef || !vertexTypeRef || vertexCount <= 0) continue;
      const typeMembers = parseTypeTree(loaded, [vertexTypeRef.section, vertexTypeRef.offset]);
      const components = vertexComponents(typeMembers);
      const stride = vertexStride(components);
      const vertexBytes = readBytes(loaded, vertexRef.section, vertexRef.offset, vertexCount * stride);
      if (vertexBytes === null) continue;
      const indexEntry = topology ? bestIndexField(topology) : null;
      const indexField = indexEntry ? indexEntry.field : null;
      const indexFieldName = indexEntry ? indexEntry.name : null;
      const indexRef = indexField?.target ?? null;
      const indexCount = indexField?.count ?? 0;
      const indexMemberType = indexMemberTypeFor(indexFieldName, indexField, MT_UINT16);
      const indices = readIndices(loaded, indexRef, indexCount, indexMemberType);
      const boneBindings = readBoneBindings(loaded, summary.fields, maxBones);
      const materials = readMaterialBindings(loaded, summary.fields, materialsByRef, maxBones);
      const triangleGroups = topology ? readTriangleGroups(loaded, topology) : [];
      const positions = readFloatComponent(vertexBytes, vertexCount, stride, components, "Position", 3, false);
      const normals = readFloatComponent(vertexBytes, vertexCount, stride, components, "Normal", 3, false);
      const uvs = readFloatComponent(vertexBytes, vertexCount, stride, components, "TextureCoordinates", 2, true);
      const vertexWeights = readVertexWeights(vertexBytes, vertexCount, stride, components, boneBindings.length);
      meshes.push(
        /** @type {MeshGeometry} */
        {
          name: summary.name,
          vertexCount,
          indexCount: indices.length,
          vertexStride: stride,
          components,
          positions,
          normals,
          uvs,
          indices,
          boneBindings,
          vertexWeights,
          materials,
          triangleGroups
        }
      );
    }
    return meshes;
  }
  function summarizeMeshes(loaded, maxMeshes) {
    const file = loaded.file;
    const rootTypeTree = parseTypeTree(loaded, file.header.root_type);
    let meshMember = null;
    for (let i = 0; i < rootTypeTree.length; i++) {
      if (rootTypeTree[i].name === "Meshes") {
        meshMember = rootTypeTree[i];
        break;
      }
    }
    if (!meshMember || !meshMember.referenceType) return [];
    const root = parseObject(loaded, rootTypeTree, file.header.root_object, { maxArrayRefs: maxMeshes });
    const meshField = root.Meshes;
    const elementRefs = meshField?.element_refs ?? [];
    if (elementRefs.length === 0) return [];
    const meshTypeRef = meshMember.referenceType;
    const meshTypeMembers = parseTypeTree(loaded, meshTypeRef);
    const meshTypeMap = {};
    for (let i = 0; i < meshTypeMembers.length; i++) {
      meshTypeMap[meshTypeMembers[i].name] = meshTypeMembers[i];
    }
    const limit = elementRefs.length < maxMeshes ? elementRefs.length : maxMeshes;
    const meshes = new Array(limit);
    let n = 0;
    for (let i = 0; i < limit; i++) {
      const meshRef = elementRefs[i];
      if (!meshRef) continue;
      const meshFields = parseObject(loaded, meshTypeMembers, [meshRef.section, meshRef.offset]);
      const nameValue = meshFields.Name?.value;
      const summary = {
        index: i,
        name: typeof nameValue === "string" && nameValue ? nameValue : `Mesh_${i}`,
        ref: meshRef,
        fields: meshFields,
        primaryVertexData: null,
        primaryTopology: null
      };
      hydrateSub(loaded, summary, meshFields, meshTypeMap, "PrimaryVertexData", "primaryVertexData");
      hydrateSub(loaded, summary, meshFields, meshTypeMap, "PrimaryTopology", "primaryTopology");
      meshes[n++] = summary;
    }
    meshes.length = n;
    return meshes;
  }
  function hydrateSub(loaded, summary, meshFields, meshTypeMap, fieldName, outputName) {
    const target = meshFields[fieldName]?.target;
    const member = meshTypeMap[fieldName];
    if (!target || !member || !member.referenceType) return;
    const subMembers = parseTypeTree(loaded, member.referenceType);
    summary[outputName] = parseObject(loaded, subMembers, [target.section, target.offset]);
  }
  function vertexComponents(members) {
    const out = new Array(members.length);
    let offset = 0;
    for (let i = 0; i < members.length; i++) {
      const member = members[i];
      const size = componentSize(member);
      out[i] = {
        name: member.name,
        offset,
        width: member.arrayWidth || 1,
        memberType: member.memberType
      };
      offset += size;
    }
    return out;
  }
  function vertexStride(components) {
    if (components.length === 0) return 0;
    let max = 0;
    for (let i = 0; i < components.length; i++) {
      const end = components[i].offset + componentStorageSize(components[i]);
      if (end > max) max = end;
    }
    return max;
  }
  function componentSize(member) {
    const width = member.arrayWidth || 1;
    const t = member.memberType;
    if (t === MT_REAL32) return 4 * width;
    if (t === MT_INT32 || t === MT_UINT32) return 4 * width;
    if (t === MT_INT16 || t === MT_UINT16 || t === MT_BINORMAL_INT16 || t === MT_NORMAL_UINT16) return 2 * width;
    if (t === MT_INT8 || t === MT_UINT8 || t === MT_BINORMAL_INT8 || t === MT_NORMAL_UINT8) return width;
    return 4 * width;
  }
  function componentStorageSize(component) {
    const width = component.width;
    const t = component.memberType;
    if (t === MT_REAL32) return 4 * width;
    if (t === MT_INT32 || t === MT_UINT32) return 4 * width;
    if (t === MT_INT16 || t === MT_UINT16 || t === MT_BINORMAL_INT16 || t === MT_NORMAL_UINT16) return 2 * width;
    if (t === MT_INT8 || t === MT_UINT8 || t === MT_BINORMAL_INT8 || t === MT_NORMAL_UINT8) return width;
    return 4 * width;
  }
  function readFloatComponent(data, vertexCount, stride, components, name, width, prefix) {
    let component = null;
    for (let i = 0; i < components.length; i++) {
      const c = components[i];
      if (c.memberType !== MT_REAL32) continue;
      if (c.width < width) continue;
      if (prefix ? c.name.startsWith(name) : c.name === name) {
        component = c;
        break;
      }
    }
    if (component === null) return [];
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    const dataLen = data.length;
    const componentOffset = component.offset;
    const elementBytes = width * 4;
    const out = [];
    for (let v = 0; v < vertexCount; v++) {
      const base = v * stride + componentOffset;
      if (base + elementBytes > dataLen) break;
      if (width === 3) {
        out.push([view.getFloat32(base, true), view.getFloat32(base + 4, true), view.getFloat32(base + 8, true)]);
      } else if (width === 2) {
        out.push([view.getFloat32(base, true), view.getFloat32(base + 4, true)]);
      } else {
        const tuple = new Array(width);
        for (let k = 0; k < width; k++) {
          tuple[k] = view.getFloat32(base + k * 4, true);
        }
        out.push(tuple);
      }
    }
    return out;
  }
  function readIndices(loaded, ref, count, memberType) {
    if (!ref || count <= 0) return [];
    if (memberType === MT_INT32 || memberType === MT_UINT32) {
      const bytes2 = readBytes(loaded, ref.section, ref.offset, count * 4);
      if (bytes2 === null) return [];
      const view2 = new DataView(bytes2.buffer, bytes2.byteOffset, bytes2.byteLength);
      const out2 = new Array(count);
      for (let i = 0; i < count; i++) {
        out2[i] = view2.getUint32(i * 4, true);
      }
      return out2;
    }
    const bytes = readBytes(loaded, ref.section, ref.offset, count * 2);
    if (bytes === null) return [];
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const out = new Array(count);
    for (let i = 0; i < count; i++) {
      out[i] = view.getUint16(i * 2, true);
    }
    return out;
  }
  function readVertexWeights(data, vertexCount, stride, components, bindingCount) {
    let weightsComponent = null;
    let indicesComponent = null;
    for (let i = 0; i < components.length; i++) {
      if (components[i].name === "BoneWeights") weightsComponent = components[i];
      else if (components[i].name === "BoneIndices") indicesComponent = components[i];
    }
    if (weightsComponent === null || indicesComponent === null || bindingCount <= 0) return [];
    const width = weightsComponent.width < indicesComponent.width ? weightsComponent.width : indicesComponent.width;
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    const dataLen = data.length;
    const out = new Array(vertexCount);
    const weightsOffset = weightsComponent.offset;
    const indicesOffset = indicesComponent.offset;
    for (let v = 0; v < vertexCount; v++) {
      const base = v * stride;
      const perVertex = [];
      for (let lane = 0; lane < width; lane++) {
        const weight = readWeightValue(view, dataLen, base + weightsOffset, lane, weightsComponent);
        const boneIndex = readIntValue(view, dataLen, base + indicesOffset, lane, indicesComponent);
        if (weight <= 0 || boneIndex < 0 || boneIndex >= bindingCount) continue;
        perVertex.push({ boneIndex, weight });
      }
      out[v] = perVertex;
    }
    return out;
  }
  function readWeightValue(view, dataLen, offset, lane, component) {
    const t = component.memberType;
    if (t === MT_REAL32) {
      const start = offset + lane * 4;
      if (start + 4 > dataLen) return 0;
      const value = view.getFloat32(start, true);
      if (value <= 0) return 0;
      return value > 1 ? 1 : value;
    }
    if (t === MT_UINT16 || t === MT_NORMAL_UINT16) {
      const start = offset + lane * 2;
      if (start + 2 > dataLen) return 0;
      const value = view.getUint16(start, true);
      return t === MT_NORMAL_UINT16 ? value / 65535 : value;
    }
    if (t === MT_UINT8 || t === MT_NORMAL_UINT8) {
      const start = offset + lane;
      if (start >= dataLen) return 0;
      const value = view.getUint8(start);
      return t === MT_NORMAL_UINT8 ? value / 255 : value;
    }
    return 0;
  }
  function readIntValue(view, dataLen, offset, lane, component) {
    const t = component.memberType;
    if (t === MT_INT32 || t === MT_UINT32) {
      const start = offset + lane * 4;
      if (start + 4 > dataLen) return -1;
      return t === MT_INT32 ? view.getInt32(start, true) : view.getUint32(start, true);
    }
    if (t === MT_INT16 || t === MT_UINT16) {
      const start = offset + lane * 2;
      if (start + 2 > dataLen) return -1;
      return t === MT_INT16 ? view.getInt16(start, true) : view.getUint16(start, true);
    }
    if (t === MT_INT8 || t === MT_UINT8) {
      const start = offset + lane;
      if (start >= dataLen) return -1;
      return t === MT_INT8 ? view.getInt8(start) : view.getUint8(start);
    }
    return -1;
  }
  function readBoneBindings(loaded, meshFields, maxBones) {
    const bindingField = meshFields.BoneBindings;
    if (!bindingField) return [];
    const objects = readReferenceArrayObjects(
      loaded,
      bindingField.target ?? null,
      bindingField.count ?? 0,
      bindingField.reference_type ?? null,
      { maxCount: maxBones }
    );
    const out = new Array(objects.length);
    for (let i = 0; i < objects.length; i++) {
      const name = objects[i].fields.BoneName?.value;
      out[i] = {
        index: i,
        name: typeof name === "string" && name ? name : `Bone_${i}`
      };
    }
    return out;
  }
  function readMaterialBindings(loaded, meshFields, materialsByRef, maxBones) {
    const bindingField = meshFields.MaterialBindings;
    if (!bindingField) return [];
    const objects = readReferenceArrayObjects(
      loaded,
      bindingField.target ?? null,
      bindingField.count ?? 0,
      bindingField.reference_type ?? null,
      { maxCount: maxBones }
    );
    const out = new Array(objects.length);
    for (let i = 0; i < objects.length; i++) {
      const materialRef = objects[i].fields.Material?.target;
      const material = materialRef ? materialsByRef[`${materialRef.section}:${materialRef.offset}`] : null;
      out[i] = material ?? {
        index: i,
        name: `Material_${i}`,
        textureFile: "",
        textureSize: null
      };
    }
    return out;
  }
  function readTriangleGroups(loaded, topologyFields) {
    const groupField = topologyFields.Groups;
    if (!groupField) return [];
    const objects = readReferenceArrayObjects(
      loaded,
      groupField.target ?? null,
      groupField.count ?? 0,
      groupField.reference_type ?? null,
      { maxCount: 4096 }
    );
    const out = new Array(objects.length);
    for (let i = 0; i < objects.length; i++) {
      const fields = objects[i].fields;
      out[i] = {
        materialIndex: typeof fields.MaterialIndex?.value === "number" ? fields.MaterialIndex.value : 0,
        triFirst: typeof fields.TriFirst?.value === "number" ? fields.TriFirst.value : 0,
        triCount: typeof fields.TriCount?.value === "number" ? fields.TriCount.value : 0
      };
    }
    return out;
  }
  function indexMemberTypeFor(fieldName, field, fallback) {
    if (!field) return fallback;
    if (fieldName === "Indices") return MT_UINT32;
    return fallback;
  }
  function bestIndexField(topologyFields) {
    const indices16 = topologyFields.Indices16 ?? null;
    const indices32 = topologyFields.Indices ?? null;
    if (indices16 && (indices16.count ?? 0) > 0) return { name: "Indices16", field: indices16 };
    if (indices32 && (indices32.count ?? 0) > 0) return { name: "Indices", field: indices32 };
    if (indices16) return { name: "Indices16", field: indices16 };
    if (indices32) return { name: "Indices", field: indices32 };
    return null;
  }
  function walkRootMaterials(loaded, maxMaterials) {
    const file = loaded.file;
    const rootTypeTree = parseTypeTree(loaded, file.header.root_type);
    const root = parseObject(loaded, rootTypeTree, file.header.root_object, { maxArrayRefs: maxMaterials });
    const materialField = root.Materials;
    if (!materialField) return { materials: [], cache: {} };
    const materialType = materialField.reference_type ?? null;
    const elementRefs = materialField.element_refs ?? [];
    const cache = {};
    const limit = elementRefs.length < maxMaterials ? elementRefs.length : maxMaterials;
    const materials = new Array(limit);
    let n = 0;
    for (let i = 0; i < limit; i++) {
      const ref = elementRefs[i];
      if (!ref) continue;
      materials[n++] = readMaterial(loaded, ref, materialType, i, cache, {});
    }
    materials.length = n;
    return { materials, cache };
  }
  function materialMap(loaded, maxMaterials) {
    return walkRootMaterials(loaded, maxMaterials).cache;
  }
  function readMaterial(loaded, ref, materialType, index, cache, seen) {
    const key = `${ref.section}:${ref.offset}`;
    if (cache[key]) return cache[key];
    if (materialType === null || seen[key]) {
      return { index, name: `Material_${index}`, textureFile: "", textureSize: null };
    }
    const materialMembers = parseTypeTree(loaded, [materialType.section, materialType.offset]);
    const fields = parseObject(loaded, materialMembers, [ref.section, ref.offset], { maxArrayRefs: 16 });
    let texture = readTextureField(loaded, fields.Texture);
    if (texture === null) {
      texture = readFirstMapTexture(loaded, fields.Maps, materialType, cache, { ...seen, [key]: true });
    }
    const nameValue = fields.Name?.value;
    const info = {
      index,
      name: typeof nameValue === "string" && nameValue ? nameValue : `Material_${index}`,
      textureFile: texture ? texture[0] : "",
      textureSize: texture ? texture[1] : null
    };
    cache[key] = info;
    return info;
  }
  function readTextureField(loaded, textureField) {
    if (!textureField) return null;
    const target = textureField.target ?? null;
    const textureType = textureField.reference_type ?? null;
    if (!target || !textureType) return null;
    const textureMembers = parseTypeTree(loaded, [textureType.section, textureType.offset]);
    const fields = parseObject(loaded, textureMembers, [target.section, target.offset], { maxArrayRefs: 8 });
    const widthValue = fields.Width?.value;
    const heightValue = fields.Height?.value;
    const size = typeof widthValue === "number" && typeof heightValue === "number" ? [widthValue, heightValue] : null;
    const fileNameValue = fields.FromFileName?.value;
    return [typeof fileNameValue === "string" ? fileNameValue : "", size];
  }
  function readFirstMapTexture(loaded, mapsField, materialType, cache, seen) {
    if (!mapsField) return null;
    const target = mapsField.target ?? null;
    const mapType = mapsField.reference_type ?? null;
    const maps = readReferenceArrayObjects(
      loaded,
      target,
      mapsField.count ?? 0,
      mapType,
      { maxCount: 16 }
    );
    for (let i = 0; i < maps.length; i++) {
      const mapRef = maps[i].fields.Map?.target;
      if (!mapRef) continue;
      const material = readMaterial(loaded, mapRef, materialType, -1, cache, seen);
      if (material.textureFile) {
        return [material.textureFile, material.textureSize];
      }
    }
    return null;
  }
  function readBytes(loaded, section, offset, size) {
    const data = loaded.sectionsOriginal[section];
    if (!data || offset < 0 || offset + size > data.length) return null;
    return data.subarray(offset, offset + size);
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/GrannySkeleton.js
  function extractSkeletons(loaded, options = {}) {
    const maxSkeletons = options.maxSkeletons ?? 16;
    const maxBones = options.maxBones ?? 4096;
    const file = loaded.file;
    const rootTypeRef = file.header.root_type;
    const rootObjectRef = file.header.root_object;
    const rootTypeTree = parseTypeTree(loaded, rootTypeRef);
    const root = parseObject(loaded, rootTypeTree, rootObjectRef, { maxArrayRefs: maxSkeletons });
    const skeletonField = root.Skeletons;
    if (!skeletonField) return [];
    const skeletonType = skeletonField.reference_type ?? null;
    const elementRefs = skeletonField.element_refs ?? [];
    if (skeletonType === null || elementRefs.length === 0) return [];
    const skeletons = [];
    const skeletonTypeMembers = parseTypeTree(loaded, [skeletonType.section, skeletonType.offset]);
    const limit = elementRefs.length < maxSkeletons ? elementRefs.length : maxSkeletons;
    for (let i = 0; i < limit; i++) {
      const skeletonRef = elementRefs[i];
      if (!skeletonRef) continue;
      const fields = parseObject(
        loaded,
        skeletonTypeMembers,
        [skeletonRef.section, skeletonRef.offset],
        { maxArrayRefs: maxBones }
      );
      const boneField = fields.Bones;
      const boneTarget = boneField?.target ?? null;
      const boneType = boneField?.reference_type ?? null;
      const boneCount = boneField?.count ?? 0;
      const boneObjects = readReferenceArrayObjects(
        loaded,
        boneTarget,
        boneCount,
        boneType,
        { maxCount: maxBones }
      );
      const bones = new Array(boneObjects.length);
      for (let b = 0; b < boneObjects.length; b++) {
        bones[b] = readBone(loaded, b, boneObjects[b]);
      }
      const nameValue = fields.Name?.value;
      const lodTypeValue = fields.LODType?.value;
      skeletons.push({
        name: typeof nameValue === "string" && nameValue ? nameValue : `Skeleton_${skeletons.length}`,
        bones,
        lodType: typeof lodTypeValue === "number" ? lodTypeValue : 0
      });
    }
    return skeletons;
  }
  function readBone(loaded, index, boneObject) {
    const { ref, fields } = boneObject;
    const nameValue = fields.Name?.value;
    const parentValue = fields.ParentIndex?.value;
    const transformOffset = fields.Transform?.offset ?? 0;
    const inverseOffset = fields.InverseWorldTransform?.offset ?? 0;
    let transform = IDENTITY_TRANSFORM;
    let inverseWorldTransform = [];
    if (ref) {
      transform = readTransform(loaded, ref.section, transformOffset);
      inverseWorldTransform = readReal32Array(loaded, ref.section, inverseOffset, 16);
    }
    return {
      index,
      name: typeof nameValue === "string" && nameValue ? nameValue : `Bone_${index}`,
      parentIndex: typeof parentValue === "number" ? parentValue : -1,
      transform,
      inverseWorldTransform
    };
  }
  function readReal32Array(loaded, section, offset, count) {
    const data = loaded.sectionsOriginal[section];
    if (!data || offset < 0 || offset + count * 4 > data.length) return [];
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    const out = new Array(count);
    for (let i = 0; i < count; i++) {
      out[i] = view.getFloat32(offset + i * 4, true);
    }
    return out;
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/GrannyModel.js
  function buildRefIndex(field) {
    const out = {};
    const refs = field?.element_refs ?? [];
    for (let i = 0; i < refs.length; i++) {
      const r = refs[i];
      if (r) out[`${r.section}:${r.offset}`] = i;
    }
    return out;
  }
  function extractModels(loaded, options = {}) {
    const maxModels = options.maxModels ?? 64;
    const maxBindings = options.maxBindings ?? 256;
    const file = loaded.file;
    const root = parseObject(
      loaded,
      parseTypeTree(loaded, file.header.root_type),
      file.header.root_object
    );
    const modelField = root.Models;
    if (!modelField) return [];
    const modelTypeRef = modelField.reference_type ?? null;
    const elementRefs = modelField.element_refs ?? [];
    if (modelTypeRef === null || elementRefs.length === 0) return [];
    const skeletonRefIndex = buildRefIndex(root.Skeletons);
    const meshRefIndex = buildRefIndex(root.Meshes);
    const modelTT = parseTypeTree(loaded, [modelTypeRef.section, modelTypeRef.offset]);
    const limit = elementRefs.length < maxModels ? elementRefs.length : maxModels;
    const out = new Array(limit);
    let n = 0;
    for (let i = 0; i < limit; i++) {
      const mref = elementRefs[i];
      if (!mref) continue;
      const fields = parseObject(loaded, modelTT, [mref.section, mref.offset]);
      const nameValue = fields.Name?.value;
      const name = typeof nameValue === "string" && nameValue ? nameValue : `Model_${n}`;
      const skelTarget = fields.Skeleton?.target ?? null;
      const skeletonIdx = skelTarget ? skeletonRefIndex[`${skelTarget.section}:${skelTarget.offset}`] ?? -1 : -1;
      const placement = fields.InitialPlacement?.value ?? readTransform(loaded, mref.section, fields.InitialPlacement?.offset ?? 0) ?? IDENTITY_TRANSFORM;
      const meshBindings = readModelMeshBindings(loaded, fields, meshRefIndex, maxBindings);
      out[n++] = {
        name,
        skeletonIdx,
        initialPlacement: placement,
        meshBindings
      };
    }
    out.length = n;
    return out;
  }
  function readModelMeshBindings(loaded, modelFields, meshRefIndex, maxBindings) {
    const mbField = modelFields.MeshBindings;
    if (!mbField) return [];
    const mbTypeRef = mbField.reference_type ?? null;
    const mbTarget = mbField.target ?? null;
    const mbCount = mbField.count ?? 0;
    if (mbTypeRef === null || mbTarget === null || mbCount <= 0) return [];
    const mbObjects = readReferenceArrayObjects(
      loaded,
      mbTarget,
      mbCount,
      mbTypeRef,
      { maxCount: maxBindings }
    );
    const out = new Array(mbObjects.length);
    let n = 0;
    for (let i = 0; i < mbObjects.length; i++) {
      const f = mbObjects[i].fields;
      const meshTarget = f.Mesh?.target ?? null;
      const meshIdx = meshTarget ? meshRefIndex[`${meshTarget.section}:${meshTarget.offset}`] ?? -1 : -1;
      out[n++] = { meshIdx };
    }
    out.length = n;
    return out;
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/GrannyAnimation.js
  var EMPTY_F32 = new Float32Array(0);
  var IDENTITY_TRANSFORM2 = Object.freeze({
    position: [0, 0, 0],
    orientation: [0, 0, 0, 1],
    scaleShear: [1, 0, 0, 0, 1, 0, 0, 0, 1]
  });
  var SCALAR_SIZES2 = {
    10: 4,
    // real32
    11: 1,
    // int8
    12: 1,
    // uint8
    13: 1,
    // binormal_int8
    14: 1,
    // normal_uint8
    15: 2,
    // int16
    16: 2,
    // uint16
    17: 2,
    // binormal_int16
    18: 2,
    // normal_uint16
    19: 4,
    // int32
    20: 4,
    // uint32
    21: 2
    // real16
  };
  var ONE_OVER_SQRT2 = 0.707106781;
  var QUATERNION_SCALE_OFFSET_TABLE = [
    [ONE_OVER_SQRT2 * 2, -ONE_OVER_SQRT2],
    [ONE_OVER_SQRT2 * 1, -ONE_OVER_SQRT2 * 0.5],
    [ONE_OVER_SQRT2 * 0.5, -ONE_OVER_SQRT2 * 0.75],
    [ONE_OVER_SQRT2 * 0.5, -ONE_OVER_SQRT2 * 0.25],
    [ONE_OVER_SQRT2 * 0.5, ONE_OVER_SQRT2 * 0.25],
    [ONE_OVER_SQRT2 * 0.25, -ONE_OVER_SQRT2 * 0.25],
    [ONE_OVER_SQRT2 * 0.25, -ONE_OVER_SQRT2 * 0.125],
    [ONE_OVER_SQRT2 * 0.25, ONE_OVER_SQRT2 * 0],
    [-ONE_OVER_SQRT2 * 2, ONE_OVER_SQRT2],
    [-ONE_OVER_SQRT2 * 1, ONE_OVER_SQRT2 * 0.5],
    [-ONE_OVER_SQRT2 * 0.5, ONE_OVER_SQRT2 * 0.75],
    [-ONE_OVER_SQRT2 * 0.5, ONE_OVER_SQRT2 * 0.25],
    [-ONE_OVER_SQRT2 * 0.5, -ONE_OVER_SQRT2 * 0.25],
    [-ONE_OVER_SQRT2 * 0.25, ONE_OVER_SQRT2 * 0.25],
    [-ONE_OVER_SQRT2 * 0.25, ONE_OVER_SQRT2 * 0.125],
    [-ONE_OVER_SQRT2 * 0.25, -ONE_OVER_SQRT2 * 0]
  ];
  var TEXT_DECODER2 = new TextDecoder("utf-8", { fatal: false });
  function readPointerAt(data, offset, pointerSize) {
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    if (pointerSize === 4) return view.getUint32(offset, true);
    const lo = view.getUint32(offset, true) >>> 0;
    const hi = view.getUint32(offset + 4, true) >>> 0;
    return hi * 4294967296 + lo;
  }
  function scalarMemberSize(member, pointerSize) {
    const width = member.arrayWidth || 1;
    const t = member.memberType;
    const scalar = SCALAR_SIZES2[t];
    if (scalar !== void 0) return scalar * width;
    if (t === MT_REFERENCE || t === MT_EMPTY_REFERENCE || t === MT_STRING) return pointerSize;
    if (t === MT_REFERENCE_TO_ARRAY || t === MT_ARRAY_OF_REFERENCES) return 4 + pointerSize;
    if (t === MT_VARIANT_REFERENCE) return pointerSize * 2;
    if (t === MT_REFERENCE_TO_VARIANT_ARRAY) return pointerSize + 4 + pointerSize;
    if (t === MT_TRANSFORM) return 68;
    if (t === MT_INLINE) return 0;
    return pointerSize;
  }
  function memberOffsetsFor(loaded, members) {
    const pointerSize = loaded.pointerSize;
    const out = /* @__PURE__ */ Object.create(null);
    let offset = 0;
    for (let i = 0; i < members.length; i++) {
      const member = members[i];
      out[member.name] = offset;
      if (member.memberType === MT_INLINE && member.referenceType) {
        const sub = parseTypeTree(loaded, member.referenceType);
        offset += objectStorageSize(loaded, sub, pointerSize, /* @__PURE__ */ new Set());
      } else {
        offset += scalarMemberSize(member, pointerSize);
      }
    }
    return out;
  }
  function floatFromHighU16(value) {
    const buf = new ArrayBuffer(4);
    const view = new DataView(buf);
    view.setUint32(0, (value & 65535) << 16, true);
    return view.getFloat32(0, true);
  }
  function curveDimension(codec) {
    if (codec.length >= 2 && codec[0] === "D") {
      const digit = codec.charCodeAt(1) - 48;
      if (digit >= 0 && digit <= 9) return digit;
    }
    return 0;
  }
  function quaternionScalesOffsets(entries, quantizedMax) {
    const scales = new Float32Array(4);
    const offsets = new Float32Array(4);
    let bits = entries >>> 0;
    for (let i = 0; i < 4; i++) {
      const index = bits & 15;
      bits >>>= 4;
      const entry = QUATERNION_SCALE_OFFSET_TABLE[index];
      scales[i] = entry[0] / quantizedMax;
      offsets[i] = entry[1];
    }
    return { scales, offsets };
  }
  function readReferenceArrayPointer(loaded, fixed, offset) {
    const pointerSize = loaded.pointerSize;
    if (offset + 4 + pointerSize > fixed.length) return null;
    const pointer = readPointerAt(fixed, offset + 4, pointerSize);
    return decodeFakePointer(pointer, loaded.sectionsFixed.length);
  }
  function readCurveKnotsControls(loaded, codec, dimension, raw, fixed, objectOffset, offsets, knotControlCount) {
    if (knotControlCount <= 0 || dimension <= 0) {
      return { knots: EMPTY_F32, controls: EMPTY_F32 };
    }
    const kcOffset = offsets.KnotsControls;
    if (kcOffset === void 0) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    const arrayRef = readReferenceArrayPointer(loaded, fixed, objectOffset + kcOffset);
    if (arrayRef === null) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    if (codec === "D3K16uC16u" || codec === "D3I1K16uC16u") {
      return decodeD3K16uC16uCurve(
        loaded,
        codec,
        dimension,
        raw,
        objectOffset,
        offsets,
        knotControlCount,
        arrayRef
      );
    }
    if (codec === "D4nK8uC7u") {
      return decodeD4nK8uC7uCurve(
        loaded,
        raw,
        objectOffset,
        offsets,
        knotControlCount,
        arrayRef
      );
    }
    if (codec === "D4nK16uC15u") {
      return decodeD4nK16uC15uCurve(
        loaded,
        raw,
        objectOffset,
        offsets,
        knotControlCount,
        arrayRef
      );
    }
    return { knots: EMPTY_F32, controls: EMPTY_F32 };
  }
  function decodeD3K16uC16uCurve(loaded, codec, dimension, raw, objectOffset, offsets, knotControlCount, arrayRef) {
    const knotCount = knotControlCount / (codec === "D3I1K16uC16u" ? 2 : dimension + 1) | 0;
    if (knotCount <= 0) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    const oneOverOffset = objectOffset + (offsets.OneOverKnotScaleTrunc ?? 2);
    const scalesOffset = objectOffset + (offsets.ControlScales ?? 4);
    const offsetsOffset = objectOffset + (offsets.ControlOffsets ?? 16);
    if (offsetsOffset + dimension * 4 > raw.length) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    const rawView = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
    const oneOver = floatFromHighU16(rawView.getUint16(oneOverOffset, true));
    if (oneOver === 0) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    const controlScales = new Float32Array(dimension);
    const controlOffsets = new Float32Array(dimension);
    for (let d = 0; d < dimension; d++) {
      controlScales[d] = rawView.getFloat32(scalesOffset + d * 4, true);
      controlOffsets[d] = rawView.getFloat32(offsetsOffset + d * 4, true);
    }
    const arrayData = loaded.sectionsFixed[arrayRef[0]];
    const byteCount = knotControlCount * 2;
    if (arrayRef[1] + byteCount > arrayData.length) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    const arrayView = new DataView(
      arrayData.buffer,
      arrayData.byteOffset + arrayRef[1],
      byteCount
    );
    const knotScale = 1 / oneOver;
    const knots = new Float32Array(knotCount);
    for (let i = 0; i < knotCount; i++) {
      knots[i] = knotScale * arrayView.getUint16(i * 2, true);
    }
    const controls = new Float32Array(knotCount * dimension);
    if (codec === "D3I1K16uC16u") {
      for (let i = 0; i < knotCount; i++) {
        const param = arrayView.getUint16((knotCount + i) * 2, true);
        const base = i * dimension;
        for (let d = 0; d < dimension; d++) {
          controls[base + d] = controlOffsets[d] + controlScales[d] * param;
        }
      }
    } else {
      for (let i = 0; i < knotCount; i++) {
        const base = i * dimension;
        const srcBase = (knotCount + i * dimension) * 2;
        for (let d = 0; d < dimension; d++) {
          const param = arrayView.getUint16(srcBase + d * 2, true);
          controls[base + d] = controlOffsets[d] + controlScales[d] * param;
        }
      }
    }
    return { knots, controls };
  }
  function decodeD4nK8uC7uCurve(loaded, raw, objectOffset, offsets, knotControlCount, arrayRef) {
    const knotCount = knotControlCount / 4 | 0;
    if (knotCount <= 0) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    const scaleEntriesOffset = objectOffset + (offsets.ScaleOffsetTableEntries ?? 2);
    const oneOverOffset = objectOffset + (offsets.OneOverKnotScale ?? 4);
    if (oneOverOffset + 4 > raw.length) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    const rawView = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
    const oneOver = rawView.getFloat32(oneOverOffset, true);
    if (oneOver === 0) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    const arrayData = loaded.sectionsFixed[arrayRef[0]];
    if (arrayRef[1] + knotControlCount > arrayData.length) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    const knotScale = 1 / oneOver;
    const knots = new Float32Array(knotCount);
    for (let i = 0; i < knotCount; i++) {
      knots[i] = knotScale * arrayData[arrayRef[1] + i];
    }
    const { scales, offsets: tableOffsets } = quaternionScalesOffsets(
      rawView.getUint16(scaleEntriesOffset, true),
      127
    );
    const controls = new Float32Array(knotCount * 4);
    const controlBase = arrayRef[1] + knotCount;
    for (let i = 0; i < knotCount; i++) {
      const cur0 = arrayData[controlBase + i * 3 + 0];
      const cur1 = arrayData[controlBase + i * 3 + 1];
      const cur2 = arrayData[controlBase + i * 3 + 2];
      const missingNegative = (cur0 & 128) !== 0;
      const missingIndex = (cur1 >> 6 & 2 | cur2 >> 7) & 3;
      const result = [0, 0, 0, 0];
      let dst = missingIndex;
      let summedSq = 0;
      const srcBytes = [cur0, cur1, cur2];
      for (let src = 0; src < 3; src++) {
        dst = dst + 1 & 3;
        const v = tableOffsets[dst] + scales[dst] * (srcBytes[src] & 127);
        result[dst] = v;
        summedSq += v * v;
      }
      const missing = Math.sqrt(Math.max(0, 1 - summedSq));
      result[missingIndex] = missingNegative ? -missing : missing;
      const base = i * 4;
      controls[base] = result[0];
      controls[base + 1] = result[1];
      controls[base + 2] = result[2];
      controls[base + 3] = result[3];
    }
    return { knots, controls };
  }
  function decodeD4nK16uC15uCurve(loaded, raw, objectOffset, offsets, knotControlCount, arrayRef) {
    const knotCount = knotControlCount / 4 | 0;
    if (knotCount <= 0) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    const scaleEntriesOffset = objectOffset + (offsets.ScaleOffsetTableEntries ?? 2);
    const oneOverOffset = objectOffset + (offsets.OneOverKnotScale ?? 4);
    if (oneOverOffset + 4 > raw.length) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    const rawView = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
    const oneOver = rawView.getFloat32(oneOverOffset, true);
    if (oneOver === 0) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    const arrayData = loaded.sectionsFixed[arrayRef[0]];
    const byteCount = knotControlCount * 2;
    if (arrayRef[1] + byteCount > arrayData.length) return { knots: EMPTY_F32, controls: EMPTY_F32 };
    const arrayView = new DataView(arrayData.buffer, arrayData.byteOffset + arrayRef[1], byteCount);
    const knotScale = 1 / oneOver;
    const knots = new Float32Array(knotCount);
    for (let i = 0; i < knotCount; i++) {
      knots[i] = knotScale * arrayView.getUint16(i * 2, true);
    }
    const { scales, offsets: tableOffsets } = quaternionScalesOffsets(
      rawView.getUint16(scaleEntriesOffset, true),
      32767
    );
    const controls = new Float32Array(knotCount * 4);
    const controlBaseShorts = knotCount;
    for (let i = 0; i < knotCount; i++) {
      const cur0 = arrayView.getUint16((controlBaseShorts + i * 3 + 0) * 2, true);
      const cur1 = arrayView.getUint16((controlBaseShorts + i * 3 + 1) * 2, true);
      const cur2 = arrayView.getUint16((controlBaseShorts + i * 3 + 2) * 2, true);
      const missingNegative = (cur0 & 32768) !== 0;
      const missingIndex = (cur1 >> 14 & 2 | cur2 >> 15) & 3;
      const result = [0, 0, 0, 0];
      let dst = missingIndex;
      let summedSq = 0;
      const srcShorts = [cur0, cur1, cur2];
      for (let src = 0; src < 3; src++) {
        dst = dst + 1 & 3;
        const v = tableOffsets[dst] + scales[dst] * (srcShorts[src] & 32767);
        result[dst] = v;
        summedSq += v * v;
      }
      const missing = Math.sqrt(Math.max(0, 1 - summedSq));
      result[missingIndex] = missingNegative ? -missing : missing;
      const base = i * 4;
      controls[base] = result[0];
      controls[base + 1] = result[1];
      controls[base + 2] = result[2];
      controls[base + 3] = result[3];
    }
    return { knots, controls };
  }
  function readStaticCurveValue(codec, dimension, raw, offset) {
    if (dimension <= 0) return EMPTY_F32;
    if (codec.endsWith("Constant32f")) {
      const controlsOffset = offset + 4;
      const byteCount = dimension * 4;
      if (controlsOffset + byteCount > raw.length) return EMPTY_F32;
      const view = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
      const out = new Float32Array(dimension);
      for (let d = 0; d < dimension; d++) {
        out[d] = view.getFloat32(controlsOffset + d * 4, true);
      }
      return out;
    }
    if (codec === "DaIdentity") {
      if (dimension === 9) return new Float32Array([1, 0, 0, 0, 1, 0, 0, 0, 1]);
      if (dimension === 4) return new Float32Array([0, 0, 0, 1]);
      return new Float32Array(dimension);
    }
    return EMPTY_F32;
  }
  function readLegacyCurveMetadata(loaded, section, offset) {
    const pointerSize = loaded.pointerSize;
    const raw = loaded.sectionsOriginal[section];
    const fixed = loaded.sectionsFixed[section];
    if (!raw || offset + 4 + (4 + pointerSize) * 2 > raw.length) return null;
    const rawView = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
    const degree = rawView.getInt32(offset, true);
    if (degree < 0 || degree > 3) return null;
    const knotCount = rawView.getUint32(offset + 4, true);
    const controlCount = rawView.getUint32(offset + 4 + pointerSize + 4, true);
    if (knotCount === 0 && controlCount === 0) return null;
    if (knotCount <= 0 || controlCount <= 0 || controlCount % knotCount !== 0) return null;
    const dimension = controlCount / knotCount | 0;
    if (dimension <= 0 || dimension > 16) return null;
    const knotsRef = decodeFakePointer(
      readPointerAt(fixed, offset + 4 + 4, pointerSize),
      loaded.sectionsFixed.length
    );
    const controlsRef = decodeFakePointer(
      readPointerAt(fixed, offset + 4 + pointerSize + 4 + 4, pointerSize),
      loaded.sectionsFixed.length
    );
    if (knotsRef === null || controlsRef === null) return null;
    const knotBytes = loaded.sectionsFixed[knotsRef[0]];
    const controlBytes = loaded.sectionsFixed[controlsRef[0]];
    if (knotsRef[1] + knotCount * 4 > knotBytes.length) return null;
    if (controlsRef[1] + controlCount * 4 > controlBytes.length) return null;
    const knotView = new DataView(knotBytes.buffer, knotBytes.byteOffset + knotsRef[1], knotCount * 4);
    const controlView = new DataView(controlBytes.buffer, controlBytes.byteOffset + controlsRef[1], controlCount * 4);
    const knots = new Float32Array(knotCount);
    for (let i = 0; i < knotCount; i++) knots[i] = knotView.getFloat32(i * 4, true);
    const controls = new Float32Array(controlCount);
    for (let i = 0; i < controlCount; i++) controls[i] = controlView.getFloat32(i * 4, true);
    const sampleValue = knotCount === 1 ? controls.slice(0, dimension) : EMPTY_F32;
    return {
      codec: "LegacyCurve32f",
      format: -1,
      degree,
      dimension,
      knotControlCount: knotCount + controlCount,
      sampleValue,
      knots,
      controls
    };
  }
  function readCurveMetadata(loaded, parentSection, curveOffset) {
    const pointerSize = loaded.pointerSize;
    const fixed = loaded.sectionsFixed[parentSection];
    if (!fixed || curveOffset + pointerSize * 2 > fixed.length) return null;
    const legacy = readLegacyCurveMetadata(loaded, parentSection, curveOffset);
    if (legacy) return legacy;
    const typeRef = decodeFakePointer(
      readPointerAt(fixed, curveOffset, pointerSize),
      loaded.sectionsFixed.length
    );
    const objectRef = decodeFakePointer(
      readPointerAt(fixed, curveOffset + pointerSize, pointerSize),
      loaded.sectionsFixed.length
    );
    if (typeRef === null || objectRef === null) return null;
    const members = parseTypeTree(loaded, typeRef);
    if (members.length === 0) return null;
    const codec = members[0].name.replace(/^CurveDataHeader_/, "");
    const offsets = memberOffsetsFor(loaded, members);
    const raw = loaded.sectionsOriginal[objectRef[0]];
    if (objectRef[1] + 2 > raw.length) return null;
    const rawView = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
    const fmt = rawView.getUint8(objectRef[1]);
    const degree = rawView.getUint8(objectRef[1] + 1);
    let dimension = curveDimension(codec);
    if (codec === "DaIdentity") {
      const dimOffset = objectRef[1] + (offsets.Dimension ?? 2);
      if (dimOffset + 2 <= raw.length) {
        dimension = rawView.getInt16(dimOffset, true);
      }
    }
    let knotControlCount = 0;
    const kcOffset = offsets.KnotsControls;
    if (kcOffset !== void 0 && objectRef[1] + kcOffset + 4 <= raw.length) {
      knotControlCount = rawView.getUint32(objectRef[1] + kcOffset, true);
    }
    const { knots, controls } = readCurveKnotsControls(
      loaded,
      codec,
      dimension,
      raw,
      loaded.sectionsFixed[objectRef[0]],
      objectRef[1],
      offsets,
      knotControlCount
    );
    return {
      codec,
      format: fmt,
      degree,
      dimension,
      knotControlCount,
      sampleValue: readStaticCurveValue(codec, dimension, raw, objectRef[1]),
      knots,
      controls
    };
  }
  function readTransformTrack(loaded, index, parsedTrack) {
    const { ref, fields } = parsedTrack;
    const nameValue = fields.Name?.value;
    const orientationField = fields.OrientationCurve ?? null;
    const positionField = fields.PositionCurve ?? null;
    const scaleShearField = fields.ScaleShearCurve ?? null;
    let flagsOffset = ref.offset + 4;
    const flagsField = fields.Flags;
    if (flagsField && typeof flagsField.offset === "number") {
      flagsOffset = flagsField.offset;
    }
    let flags = 0;
    const raw = loaded.sectionsOriginal[ref.section];
    if (raw && flagsOffset + 4 <= raw.length) {
      const view = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
      flags = view.getInt32(flagsOffset, true);
    }
    return {
      index,
      name: typeof nameValue === "string" && nameValue ? nameValue : `TransformTrack_${index}`,
      flags,
      orientationCurve: orientationField ? readCurveMetadata(loaded, ref.section, orientationField.offset) : null,
      positionCurve: positionField ? readCurveMetadata(loaded, ref.section, positionField.offset) : null,
      scaleShearCurve: scaleShearField ? readCurveMetadata(loaded, ref.section, scaleShearField.offset) : null
    };
  }
  function readTransformTracks(loaded, field, maxTracks) {
    const target = field?.target ?? null;
    const typeRef = field?.reference_type ?? null;
    const count = field?.count ?? 0;
    if (target === null || typeRef === null || count <= 0) return [];
    const parsed = readReferenceArrayObjects(loaded, target, count, typeRef, {
      maxCount: maxTracks,
      maxArrayRefs: 64
    });
    const out = new Array(parsed.length);
    for (let i = 0; i < parsed.length; i++) {
      out[i] = readTransformTrack(loaded, i, parsed[i]);
    }
    return out;
  }
  function readVectorTrackNames(loaded, field, maxCount) {
    const target = field?.target ?? null;
    const typeRef = field?.reference_type ?? null;
    const count = field?.count ?? 0;
    if (target === null || typeRef === null || count <= 0) return [];
    const parsed = readReferenceArrayObjects(loaded, target, count, typeRef, {
      maxCount,
      maxArrayRefs: 64
    });
    const names = new Array(parsed.length);
    for (let i = 0; i < parsed.length; i++) {
      const value = parsed[i].fields.Name?.value;
      names[i] = typeof value === "string" && value ? value : `Track_${i}`;
    }
    return names;
  }
  function readTrackGroup(loaded, index, ref, typeMembers, maxTracks) {
    const fields = parseObject(loaded, typeMembers, [ref.section, ref.offset], {
      maxArrayRefs: maxTracks
    });
    const transformTracks = readTransformTracks(loaded, fields.TransformTracks, maxTracks);
    const nameValue = fields.Name?.value;
    return {
      index,
      name: typeof nameValue === "string" && nameValue ? nameValue : `TrackGroup_${index}`,
      vectorTrackCount: fields.VectorTracks?.count ?? 0,
      transformTrackCount: fields.TransformTracks?.count ?? 0,
      textTrackCount: fields.TextTracks?.count ?? 0,
      accumulationFlags: fields.AccumulationFlags?.value ?? 0,
      loopTranslation: fields.LoopTranslation?.value ?? 0,
      vectorTrackNames: readVectorTrackNames(loaded, fields.VectorTracks, maxTracks),
      transformTracks
    };
  }
  function readTrackGroupReferenceNames(loaded, field, maxRefs) {
    const target = field?.target ?? null;
    const typeRef = field?.reference_type ?? null;
    const count = field?.count ?? 0;
    if (target === null || count <= 0) return [];
    const elementRefs = field?.element_refs ?? [];
    const names = new Array(elementRefs.length);
    if (typeRef === null) {
      for (let i = 0; i < elementRefs.length; i++) names[i] = `TrackGroup_${i}`;
      return names;
    }
    const typeMembers = parseTypeTree(loaded, [typeRef.section, typeRef.offset]);
    const limit = Math.min(elementRefs.length, maxRefs);
    for (let i = 0; i < limit; i++) {
      const element = elementRefs[i];
      const fields = parseObject(loaded, typeMembers, [element.section, element.offset], {
        maxArrayRefs: 0
      });
      const value = fields.Name?.value;
      names[i] = typeof value === "string" && value ? value : `TrackGroup_${i}`;
    }
    names.length = limit;
    return names;
  }
  function readAnimation(loaded, index, ref, typeMembers, trackGroupByName) {
    const fields = parseObject(loaded, typeMembers, [ref.section, ref.offset], {
      maxArrayRefs: 64
    });
    const nameValue = fields.Name?.value;
    const trackGroupNames = readTrackGroupReferenceNames(loaded, fields.TrackGroups, 64);
    const trackGroups = [];
    for (let i = 0; i < trackGroupNames.length; i++) {
      const tg = trackGroupByName[trackGroupNames[i]];
      if (tg) trackGroups.push(tg);
    }
    return {
      index,
      name: typeof nameValue === "string" && nameValue ? nameValue : `Animation_${index}`,
      duration: fields.Duration?.value ?? 0,
      timeStep: fields.TimeStep?.value ?? 0,
      oversampling: fields.Oversampling?.value ?? 0,
      defaultLoopCount: fields.DefaultLoopCount?.value ?? 0,
      flags: fields.Flags?.value ?? 0,
      trackGroupNames,
      trackGroups
    };
  }
  function extractAnimations(loaded, options = {}) {
    const maxTrackGroups = options.maxTrackGroups ?? 64;
    const maxTracksPerGroup = options.maxTracksPerGroup ?? 512;
    const maxAnimations = options.maxAnimations ?? 64;
    const file = loaded.file;
    const rootTypeTree = parseTypeTree(loaded, file.header.root_type);
    const root = parseObject(loaded, rootTypeTree, file.header.root_object, {
      maxArrayRefs: Math.max(maxTrackGroups, maxAnimations)
    });
    const trackGroupField = root.TrackGroups;
    const trackGroups = [];
    if (trackGroupField) {
      const tgTypeRef = trackGroupField.reference_type ?? null;
      const tgRefs = trackGroupField.element_refs ?? [];
      if (tgTypeRef !== null && tgRefs.length > 0) {
        const tgTypeMembers = parseTypeTree(loaded, [tgTypeRef.section, tgTypeRef.offset]);
        const limit = Math.min(tgRefs.length, maxTrackGroups);
        for (let i = 0; i < limit; i++) {
          trackGroups.push(readTrackGroup(loaded, i, tgRefs[i], tgTypeMembers, maxTracksPerGroup));
        }
      }
    }
    const animationField = root.Animations;
    const animations = [];
    if (animationField) {
      const animTypeRef = animationField.reference_type ?? null;
      const animRefs = animationField.element_refs ?? [];
      if (animTypeRef !== null && animRefs.length > 0) {
        const animTypeMembers = parseTypeTree(loaded, [animTypeRef.section, animTypeRef.offset]);
        const trackGroupByName = /* @__PURE__ */ Object.create(null);
        for (let i = 0; i < trackGroups.length; i++) {
          trackGroupByName[trackGroups[i].name] = trackGroups[i];
        }
        const limit = Math.min(animRefs.length, maxAnimations);
        for (let i = 0; i < limit; i++) {
          animations.push(readAnimation(loaded, i, animRefs[i], animTypeMembers, trackGroupByName));
        }
      }
    }
    return (
      /** @type {readonly Animation[]} */
      animations
    );
  }
  function findKnot(knots, t) {
    const n = knots.length;
    for (let i = 0; i < n; i++) {
      if (knots[i] > t) return i;
    }
    return n > 0 ? n - 1 : 0;
  }
  function safeDiv(numerator, denominator) {
    if (Math.abs(denominator) < 1e-12) return 0;
    return numerator / denominator;
  }
  function linearCoefficients(tiPrev, tiCurr, t) {
    const blend = safeDiv(t - tiPrev, tiCurr - tiPrev);
    return [1 - blend, blend];
  }
  function quadraticCoefficients(ti2, ti1, ti, ti1Next, t) {
    const l0 = safeDiv(t - ti1, ti - ti1);
    const l1_1 = safeDiv(t - ti2, ti - ti2);
    const l1_2 = safeDiv(t - ti1, ti1Next - ti1);
    const ci2PlusCi1 = l1_1 + l0 - l0 * l1_1;
    const ci = l0 * l1_2;
    const ci_1 = ci2PlusCi1 - ci;
    const ci_2 = 1 - ci2PlusCi1;
    return [ci_2, ci_1, ci];
  }
  function normalizeQuaternionFast(values) {
    const x = values[0], y = values[1], z = values[2], w = values[3];
    const lengthSq = x * x + y * y + z * z + w * w;
    const factor = (3 - lengthSq) * 0.5;
    return [x * factor, y * factor, z * factor, w * factor];
  }
  function controlAt(controls, dimension, knotIndex) {
    const knotCount = controls.length / dimension;
    const idx = knotIndex < knotCount ? knotIndex : knotCount - 1;
    const base = idx * dimension;
    const out = new Array(dimension);
    for (let d = 0; d < dimension; d++) out[d] = controls[base + d];
    return out;
  }
  function evaluateCurve(curve, t) {
    if (!curve) return null;
    const knots = curve.knots;
    const controls = curve.controls;
    const dimension = curve.dimension;
    if (knots.length === 0 || controls.length === 0) {
      if (curve.sampleValue.length > 0) {
        const out = new Array(curve.sampleValue.length);
        for (let i = 0; i < out.length; i++) out[i] = curve.sampleValue[i];
        return out;
      }
      return null;
    }
    const degree = curve.degree > 0 ? curve.degree | 0 : 0;
    if (degree === 0 || knots.length === 1) {
      const knotIndex2 = findKnot(knots, t);
      return controlAt(controls, dimension, knotIndex2);
    }
    const knotIndex = findKnot(knots, t);
    const clampedKnot = knotIndex < knots.length ? knotIndex : knots.length - 1;
    const window = 2 * degree;
    const base = clampedKnot - degree;
    const ti = new Array(window);
    const pi = new Array(window);
    for (let local = 0; local < window; local++) {
      let source = base + local;
      if (source < 0) source = 0;
      if (source > knots.length - 1) source = knots.length - 1;
      ti[local] = knots[source];
      pi[local] = controlAt(controls, dimension, source);
    }
    const center = degree;
    let result;
    if (degree === 1) {
      const [cPrev, cCurr] = linearCoefficients(ti[center - 1], ti[center], t);
      result = new Array(dimension);
      for (let d = 0; d < dimension; d++) {
        result[d] = cPrev * pi[center - 1][d] + cCurr * pi[center][d];
      }
    } else if (degree === 2) {
      const [c2, c1, c0] = quadraticCoefficients(
        ti[center - 2],
        ti[center - 1],
        ti[center],
        ti[center + 1],
        t
      );
      result = new Array(dimension);
      for (let d = 0; d < dimension; d++) {
        result[d] = c2 * pi[center - 2][d] + c1 * pi[center - 1][d] + c0 * pi[center][d];
      }
    } else {
      result = pi[center];
    }
    if (dimension === 4) return normalizeQuaternionFast(result);
    return result;
  }
  function shapeTransformComponent(values, targetLength, identity) {
    if (!values) return identity;
    if (values.length === targetLength) return values;
    if (targetLength === 9 && values.length === 3) {
      return [values[0], 0, 0, 0, values[1], 0, 0, 0, values[2]];
    }
    return identity;
  }
  function evaluateTransformTrack(track, t) {
    const positionRaw = evaluateCurve(track?.positionCurve, t);
    const orientationRaw = evaluateCurve(track?.orientationCurve, t);
    const scaleShearRaw = evaluateCurve(track?.scaleShearCurve, t);
    return (
      /** @type {EvaluatedTransform} */
      {
        position: shapeTransformComponent(positionRaw, 3, [...IDENTITY_TRANSFORM2.position]),
        orientation: shapeTransformComponent(orientationRaw, 4, [...IDENTITY_TRANSFORM2.orientation]),
        scaleShear: shapeTransformComponent(scaleShearRaw, 9, [...IDENTITY_TRANSFORM2.scaleShear])
      }
    );
  }
  function evaluateAnimation(animation, t) {
    const out = /* @__PURE__ */ Object.create(null);
    if (!animation) return out;
    const groups = animation.trackGroups ?? [];
    for (let g = 0; g < groups.length; g++) {
      const tracks = groups[g].transformTracks ?? [];
      for (let i = 0; i < tracks.length; i++) {
        out[tracks[i].name] = evaluateTransformTrack(tracks[i], t);
      }
    }
    return out;
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/GrannyPose.js
  var IDENTITY_MAT4 = Object.freeze([
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1
  ]);
  var IDENTITY_TRANSFORM3 = Object.freeze({
    flags: 0,
    position: [0, 0, 0],
    orientation: [0, 0, 0, 1],
    scaleShear: [1, 0, 0, 0, 1, 0, 0, 0, 1]
  });
  var IWT_TRANSPOSE_ON_LOAD = false;
  function composeLocalMatrix(transform) {
    const t = transform ?? IDENTITY_TRANSFORM3;
    const pos = t.position ?? IDENTITY_TRANSFORM3.position;
    const quat = t.orientation ?? IDENTITY_TRANSFORM3.orientation;
    const ss = t.scaleShear ?? IDENTITY_TRANSFORM3.scaleShear;
    const px = pos[0], py = pos[1], pz = pos[2];
    const qx = quat[0], qy = quat[1], qz = quat[2], qw = quat[3];
    const xx = qx * qx, yy = qy * qy, zz = qz * qz;
    const xy = qx * qy, xz = qx * qz, yz = qy * qz;
    const wx = qw * qx, wy = qw * qy, wz = qw * qz;
    const r00 = 1 - 2 * (yy + zz);
    const r01 = 2 * (xy - wz);
    const r02 = 2 * (xz + wy);
    const r10 = 2 * (xy + wz);
    const r11 = 1 - 2 * (xx + zz);
    const r12 = 2 * (yz - wx);
    const r20 = 2 * (xz - wy);
    const r21 = 2 * (yz + wx);
    const r22 = 1 - 2 * (xx + yy);
    const s00 = ss[0], s01 = ss[1], s02 = ss[2];
    const s10 = ss[3], s11 = ss[4], s12 = ss[5];
    const s20 = ss[6], s21 = ss[7], s22 = ss[8];
    const m00 = r00 * s00 + r01 * s10 + r02 * s20;
    const m01 = r00 * s01 + r01 * s11 + r02 * s21;
    const m02 = r00 * s02 + r01 * s12 + r02 * s22;
    const m10 = r10 * s00 + r11 * s10 + r12 * s20;
    const m11 = r10 * s01 + r11 * s11 + r12 * s21;
    const m12 = r10 * s02 + r11 * s12 + r12 * s22;
    const m20 = r20 * s00 + r21 * s10 + r22 * s20;
    const m21 = r20 * s01 + r21 * s11 + r22 * s21;
    const m22 = r20 * s02 + r21 * s12 + r22 * s22;
    const out = new Float32Array(16);
    out[0] = m00;
    out[1] = m10;
    out[2] = m20;
    out[3] = 0;
    out[4] = m01;
    out[5] = m11;
    out[6] = m21;
    out[7] = 0;
    out[8] = m02;
    out[9] = m12;
    out[10] = m22;
    out[11] = 0;
    out[12] = px;
    out[13] = py;
    out[14] = pz;
    out[15] = 1;
    return out;
  }
  function multiplyMat4(a, b, out) {
    const dst = out ?? new Float32Array(16);
    const a00 = a[0], a10 = a[1], a20 = a[2], a30 = a[3];
    const a01 = a[4], a11 = a[5], a21 = a[6], a31 = a[7];
    const a02 = a[8], a12 = a[9], a22 = a[10], a32 = a[11];
    const a03 = a[12], a13 = a[13], a23 = a[14], a33 = a[15];
    for (let col = 0; col < 4; col++) {
      const b0 = b[col * 4 + 0];
      const b1 = b[col * 4 + 1];
      const b2 = b[col * 4 + 2];
      const b3 = b[col * 4 + 3];
      dst[col * 4 + 0] = a00 * b0 + a01 * b1 + a02 * b2 + a03 * b3;
      dst[col * 4 + 1] = a10 * b0 + a11 * b1 + a12 * b2 + a13 * b3;
      dst[col * 4 + 2] = a20 * b0 + a21 * b1 + a22 * b2 + a23 * b3;
      dst[col * 4 + 3] = a30 * b0 + a31 * b1 + a32 * b2 + a33 * b3;
    }
    return dst;
  }
  function composeWorldPose(skeleton, localMatrices) {
    const bones = skeleton.bones;
    const count = bones.length;
    const f64Worlds = new Array(count);
    for (let i = 0; i < count; i++) {
      const bone = bones[i];
      const local = localMatrices[i];
      const parent = bone.parentIndex;
      if (parent < 0 || parent >= i) {
        f64Worlds[i] = mat4ToArray(local);
      } else {
        f64Worlds[i] = multiplyMat4(f64Worlds[parent], local, new Array(16));
      }
    }
    const out = new Array(count);
    for (let i = 0; i < count; i++) {
      out[i] = new Float32Array(f64Worlds[i]);
    }
    return out;
  }
  function composeSkinningMatrices(skeleton, worldMatrices) {
    const bones = skeleton.bones;
    const count = bones.length;
    const out = new Array(count);
    for (let i = 0; i < count; i++) {
      const iwt = boneIwtAsArray(bones[i]);
      const f64Skin = multiplyMat4(worldMatrices[i], iwt, new Array(16));
      out[i] = new Float32Array(f64Skin);
    }
    return out;
  }
  function poseSkeletonAt(skeleton, animation, t) {
    const bones = skeleton.bones;
    const count = bones.length;
    const evaluated = animation ? evaluateAnimation(animation, t) : null;
    const localTransforms = new Array(count);
    const localMatricesF64 = new Array(count);
    for (let i = 0; i < count; i++) {
      const bone = bones[i];
      const sampled = evaluated ? evaluated[bone.name] : null;
      const local = sampled ?? bone.transform;
      localTransforms[i] = local;
      localMatricesF64[i] = composeLocalMatrixF64(local);
    }
    const worldMatrices = composeWorldPose(skeleton, localMatricesF64);
    const skinningMatrices = composeSkinningMatrices(skeleton, worldMatrices);
    return { localTransforms, worldMatrices, skinningMatrices };
  }
  function composeLocalMatrixF64(transform) {
    const t = transform ?? IDENTITY_TRANSFORM3;
    const pos = t.position ?? IDENTITY_TRANSFORM3.position;
    const quat = t.orientation ?? IDENTITY_TRANSFORM3.orientation;
    const ss = t.scaleShear ?? IDENTITY_TRANSFORM3.scaleShear;
    const px = pos[0], py = pos[1], pz = pos[2];
    const qx = quat[0], qy = quat[1], qz = quat[2], qw = quat[3];
    const xx = qx * qx, yy = qy * qy, zz = qz * qz;
    const xy = qx * qy, xz = qx * qz, yz = qy * qz;
    const wx = qw * qx, wy = qw * qy, wz = qw * qz;
    const r00 = 1 - 2 * (yy + zz);
    const r01 = 2 * (xy - wz);
    const r02 = 2 * (xz + wy);
    const r10 = 2 * (xy + wz);
    const r11 = 1 - 2 * (xx + zz);
    const r12 = 2 * (yz - wx);
    const r20 = 2 * (xz - wy);
    const r21 = 2 * (yz + wx);
    const r22 = 1 - 2 * (xx + yy);
    const s00 = ss[0], s01 = ss[1], s02 = ss[2];
    const s10 = ss[3], s11 = ss[4], s12 = ss[5];
    const s20 = ss[6], s21 = ss[7], s22 = ss[8];
    const m00 = r00 * s00 + r01 * s10 + r02 * s20;
    const m01 = r00 * s01 + r01 * s11 + r02 * s21;
    const m02 = r00 * s02 + r01 * s12 + r02 * s22;
    const m10 = r10 * s00 + r11 * s10 + r12 * s20;
    const m11 = r10 * s01 + r11 * s11 + r12 * s21;
    const m12 = r10 * s02 + r11 * s12 + r12 * s22;
    const m20 = r20 * s00 + r21 * s10 + r22 * s20;
    const m21 = r20 * s01 + r21 * s11 + r22 * s21;
    const m22 = r20 * s02 + r21 * s12 + r22 * s22;
    return [
      m00,
      m10,
      m20,
      0,
      // col 0
      m01,
      m11,
      m21,
      0,
      // col 1
      m02,
      m12,
      m22,
      0,
      // col 2
      px,
      py,
      pz,
      1
      // col 3
    ];
  }
  function mat4ToArray(src) {
    const out = new Array(16);
    for (let i = 0; i < 16; i++) out[i] = src[i];
    return out;
  }
  function boneIwtAsArray(bone) {
    const src = bone.inverseWorldTransform;
    if (!src || src.length !== 16) return [...IDENTITY_MAT4];
    const dst = new Array(16);
    if (IWT_TRANSPOSE_ON_LOAD) {
      for (let r = 0; r < 4; r++) {
        for (let c = 0; c < 4; c++) {
          dst[c * 4 + r] = src[r * 4 + c];
        }
      }
    } else {
      for (let i = 0; i < 16; i++) dst[i] = src[i];
    }
    return dst;
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/igc-yuv.js
  var PLANE_VALUE_OFFSET = 0;
  function yuvToRGB(yp, up, vp, ap, width, height) {
    const count = width * height;
    const out = new Uint8Array(count * 4);
    let o = 0;
    for (let i = 0; i < count; i++) {
      let r = up[i] + PLANE_VALUE_OFFSET;
      let g = yp[i] + PLANE_VALUE_OFFSET;
      let b = vp[i] + PLANE_VALUE_OFFSET;
      let a = ap[i];
      g -= (r + b) / 4 | 0;
      r += g;
      b += g;
      if (r < 0) r = 0;
      else if (r > 255) r = 255;
      if (g < 0) g = 0;
      else if (g > 255) g = 255;
      if (b < 0) b = 0;
      else if (b > 255) b = 255;
      if (a < 0) a = 0;
      else if (a > 255) a = 255;
      out[o] = r;
      out[o + 1] = g;
      out[o + 2] = b;
      out[o + 3] = a;
      o += 4;
    }
    return out;
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/igc-plane.js
  function varBitsOpen(buf, offset) {
    return { buf, cur: offset | 0, bits: 0, bitlen: 0 };
  }
  function varBitsReadU32LE(buf, offset) {
    return (buf[offset] | buf[offset + 1] << 8 | buf[offset + 2] << 16 | buf[offset + 3] << 24) >>> 0;
  }
  function varBitsGet1(vb) {
    let bitlen = vb.bitlen;
    let bits;
    if (bitlen === 0) {
      const i = varBitsReadU32LE(vb.buf, vb.cur);
      vb.cur = vb.cur + 4 | 0;
      bits = i >>> 1;
      bitlen = 31;
      vb.bits = bits;
      vb.bitlen = bitlen;
      return i & 1;
    }
    bits = vb.bits;
    vb.bits = bits >>> 1;
    vb.bitlen = bitlen - 1;
    return bits & 1;
  }
  function varBitsGet(vb, len) {
    const mask = len === 32 ? 4294967295 : (1 << len) - 1 >>> 0;
    if (vb.bitlen < len) {
      const nb = varBitsReadU32LE(vb.buf, vb.cur);
      vb.cur = vb.cur + 4 | 0;
      const merged = (vb.bits | nb << vb.bitlen) >>> 0 & mask;
      vb.bits = nb >>> len - vb.bitlen >>> 0;
      vb.bitlen = vb.bitlen + 32 - len;
      return merged >>> 0;
    }
    const result = vb.bits & mask;
    vb.bits = vb.bits >>> len >>> 0;
    vb.bitlen -= len;
    return result >>> 0;
  }
  function s16(v) {
    return v & 32768 ? v | 4294901760 | 0 : v | 0;
  }
  var MIN_ZERO_LENGTH = 3;
  var LIT_LENGTH_BITS = 6;
  var ZERO_LENGTH_BITS = 8;
  var LIT_LENGTH_LIMIT = (1 << LIT_LENGTH_BITS) - 1;
  var ZERO_LENGTH_LIMIT = (1 << ZERO_LENGTH_BITS) - 1;
  var EXTRA_LENGTHS = 4;
  var EXTRA_LIT_LENGTHS = [128, 256, 512, 1024];
  var EXTRA_ZERO_LENGTHS = [512, 1024, 2048, 3072];
  function getBitLevel(value) {
    let n = value >>> 0;
    if (n === 0) return 0;
    if (n >= 16384) return 15;
    let r = 0;
    while (n > 0) {
      r++;
      n >>>= 1;
    }
    return r;
  }
  function fillRect(outp, outOffset, pitch, width, height, val) {
    const yadj = pitch - width;
    let o = outOffset;
    for (let h = 0; h < height; h++) {
      for (let w = 0; w < width; w++) {
        outp[o++] = val;
      }
      o += yadj;
    }
  }
  function readEscapes(ab, mask, count) {
    const zeros = arithBitsGetValue(ab, count + 1);
    for (let i = 0; i < count; i++) {
      if (arithBitsGet(ab, count) >= zeros) {
        mask[i] = 1;
        arithBitsRemove(ab, zeros, count - zeros, count);
      } else {
        mask[i] = 0;
        arithBitsRemove(ab, 0, zeros, count);
      }
    }
  }
  function decodeLow(ab, vb, outp, outOffset, pixelPitch, encWidth, encHeight) {
    if (varBitsGet1(vb)) {
      const v = varBitsGet(vb, 16);
      fillRect(outp, outOffset, pixelPitch, encWidth, encHeight, s16(v));
      return;
    }
    const max = varBitsGet(vb, 16);
    const num = max + 1;
    const a = arithOpen(max, num);
    const yadj = pixelPitch - encWidth;
    let prev = varBitsGet(vb, 16);
    outp[outOffset++] = s16(prev);
    prev = s16(prev);
    for (let w = 0; w < encWidth - 1; w++) {
      let cur = arithDecompress(a, ab);
      if (arithWasEscaped(cur)) {
        const escaped = arithBitsGetValue(ab, num);
        arithSetDecompressed(cur, escaped, a);
        cur = escaped;
      }
      if (cur) {
        const v = -varBitsGet1(vb) | 0;
        cur = (cur ^ v) - v;
      }
      prev = cur + prev | 0;
      outp[outOffset++] = prev;
    }
    for (let h = 0; h < encHeight - 1; h++) {
      outOffset += yadj;
      let from = outOffset - pixelPitch;
      let cur = arithDecompress(a, ab);
      if (arithWasEscaped(cur)) {
        const escaped = arithBitsGetValue(ab, num);
        arithSetDecompressed(cur, escaped, a);
        cur = escaped;
      }
      if (cur) {
        const v = -varBitsGet1(vb) | 0;
        cur = (cur ^ v) - v;
      }
      prev = cur + outp[from] | 0;
      outp[outOffset++] = prev;
      ++from;
      for (let w = 0; w < encWidth - 1; w++) {
        cur = arithDecompress(a, ab);
        if (arithWasEscaped(cur)) {
          const escaped = arithBitsGetValue(ab, num);
          arithSetDecompressed(cur, escaped, a);
          cur = escaped;
        }
        if (cur) {
          const v = -varBitsGet1(vb) | 0;
          cur = (cur ^ v) - v;
        }
        prev = cur + ((prev + outp[from]) / 2 | 0) | 0;
        outp[outOffset++] = prev;
        ++from;
      }
    }
  }
  function createDecompContexts(max, num, numl) {
    const contexts = new Array(numl);
    for (let i = 0; i < numl; i++) {
      contexts[i] = arithOpen(max, num);
    }
    const lits = arithOpen(LIT_LENGTH_LIMIT, LIT_LENGTH_LIMIT + 1);
    const zeros = arithOpen(ZERO_LENGTH_LIMIT, ZERO_LENGTH_LIMIT + 1);
    return { contexts, lits, zeros };
  }
  function radabs(v) {
    return v < 0 ? -v : v;
  }
  function decodeHigh1(ab, vb, outp, outOffset, pixelPitch, encWidth, encHeight) {
    const qlevel = varBitsGet(vb, 16);
    if (varBitsGet1(vb)) {
      const v = s16(varBitsGet(vb, 16));
      fillRect(outp, outOffset, pixelPitch, encWidth, encHeight, v * qlevel | 0);
      return;
    }
    const max = varBitsGet(vb, 16);
    const num = max + 1;
    let numl = max * qlevel;
    numl = getBitLevel(numl) + 1;
    const { contexts: a, lits, zeros } = createDecompContexts(max, num, numl);
    const yadj = pixelPitch - encWidth;
    let h = encHeight;
    let above = arithBitsGetValue(ab, num);
    if (above) {
      const v = -varBitsGet1(vb) | 0;
      above = (above ^ v) - v;
      above = above * qlevel | 0;
    }
    outp[outOffset] = above;
    let aboveLeft = above;
    let prev = above;
    let fromOffset = outOffset;
    ++outOffset;
    if (encWidth === 1) {
      return decodeHigh1AfterFirst(
        ab,
        vb,
        outp,
        outOffset,
        pixelPitch,
        encWidth,
        encHeight,
        a,
        lits,
        zeros,
        num,
        numl,
        qlevel,
        yadj,
        h,
        above,
        aboveLeft,
        prev,
        fromOffset
      );
    }
    let w = encWidth - 1;
    let litLen = 0;
    let zeroLen = 0;
    let idleIter = 0;
    outer: for (; ; ) {
      let litLenRet = arithDecompress(lits, ab);
      if (arithWasEscaped(litLenRet)) {
        const escaped = varBitsGet(vb, LIT_LENGTH_BITS);
        arithSetDecompressed(litLenRet, escaped, lits);
        litLen = escaped;
      } else {
        litLen = litLenRet;
      }
      if (litLen >= LIT_LENGTH_LIMIT - EXTRA_LENGTHS + 1) {
        litLen = EXTRA_LIT_LENGTHS[litLen - (LIT_LENGTH_LIMIT - EXTRA_LENGTHS + 1)];
      }
      let zeroLenRet = arithDecompress(zeros, ab);
      if (arithWasEscaped(zeroLenRet)) {
        const escaped = varBitsGet(vb, ZERO_LENGTH_BITS);
        arithSetDecompressed(zeroLenRet, escaped, zeros);
        zeroLen = escaped;
      } else {
        zeroLen = zeroLenRet;
      }
      if (zeroLen >= ZERO_LENGTH_LIMIT - EXTRA_LENGTHS + 1) {
        zeroLen = EXTRA_ZERO_LENGTHS[zeroLen - (ZERO_LENGTH_LIMIT - EXTRA_LENGTHS + 1)] + MIN_ZERO_LENGTH - 1;
      } else if (zeroLen) {
        zeroLen += MIN_ZERO_LENGTH - 1;
      }
      if (litLen === 0 && zeroLen === 0) {
        if (++idleIter > 64) {
          throw new Error(`decodeHigh1: stuck at h=${h} w=${w} after ${idleIter} consecutive arith reads with litLen=0/zeroLen=0 \u2014 bitstream likely off-corpus (granny2.dll hangs on the same input). Encoding=${encWidth}x${encHeight}.`);
        }
      } else {
        idleIter = 0;
      }
      while (litLen > 0) {
        if (w <= 1) {
          if (w) {
            const __sum3 = radabs(Math.imul(prev, 2)) + radabs(aboveLeft) + radabs(above) >>> 0;
            let context = __sum3 / 4 >>> 0;
            context = getBitLevel(context);
            let cur = arithDecompress(a[context], ab);
            if (arithWasEscaped(cur)) {
              const escaped = arithBitsGetValue(ab, num);
              arithSetDecompressed(cur, escaped, a[context]);
              cur = escaped;
            }
            if (cur) {
              const v = -varBitsGet1(vb) | 0;
              cur = (cur ^ v) - v;
              cur = cur * qlevel | 0;
            }
            outp[outOffset++] = cur;
            --litLen;
          }
          if (--h === 0) return;
          w = encWidth;
          outOffset += yadj;
          fromOffset = outOffset - pixelPitch;
          above = outp[fromOffset++];
          aboveLeft = above;
          prev = above;
        } else {
          const aboveRight = outp[fromOffset];
          const __sum4 = radabs(prev) + radabs(aboveLeft) + radabs(above) + radabs(aboveRight) >>> 0;
          let context = __sum4 / 4 >>> 0;
          context = getBitLevel(context);
          let cur = arithDecompress(a[context], ab);
          if (arithWasEscaped(cur)) {
            const escaped = arithBitsGetValue(ab, num);
            arithSetDecompressed(cur, escaped, a[context]);
            cur = escaped;
          }
          if (cur) {
            const v = -varBitsGet1(vb) | 0;
            cur = (cur ^ v) - v;
            cur = cur * qlevel | 0;
          }
          outp[outOffset] = cur;
          aboveLeft = above;
          above = aboveRight;
          prev = cur;
          ++outOffset;
          ++fromOffset;
          --w;
          --litLen;
        }
      }
      while (zeroLen > 0) {
        if (zeroLen >= w) {
          zeroLen -= w;
          fromOffset += w;
          while (w-- > 0) {
            outp[outOffset++] = 0;
          }
          if (--h === 0) return;
          w = encWidth;
          outOffset += yadj;
          fromOffset = outOffset - pixelPitch;
          above = outp[fromOffset++];
          aboveLeft = above;
          prev = above;
        } else {
          w -= zeroLen;
          fromOffset += zeroLen;
          do {
            outp[outOffset++] = 0;
          } while (--zeroLen > 0);
          prev = 0;
          above = outp[fromOffset - 1];
          aboveLeft = outp[fromOffset - 2];
        }
      }
    }
  }
  function decodeHigh1AfterFirst(ab, vb, outp, outOffset, pixelPitch, encWidth, encHeight, a, lits, zeros, num, numl, qlevel, yadj, hIn, aboveIn, aboveLeftIn, prevIn, fromOffsetIn) {
    let h = hIn;
    let above = aboveIn;
    let aboveLeft = aboveLeftIn;
    let prev = prevIn;
    let fromOffset = fromOffsetIn;
    if (--h === 0) return;
    let w = encWidth;
    outOffset += yadj;
    fromOffset = outOffset - pixelPitch;
    above = outp[fromOffset++];
    aboveLeft = above;
    prev = above;
    let litLen = 0;
    let zeroLen = 0;
    let idleIter = 0;
    for (; ; ) {
      let litLenRet = arithDecompress(lits, ab);
      if (arithWasEscaped(litLenRet)) {
        const escaped = varBitsGet(vb, LIT_LENGTH_BITS);
        arithSetDecompressed(litLenRet, escaped, lits);
        litLen = escaped;
      } else {
        litLen = litLenRet;
      }
      if (litLen >= LIT_LENGTH_LIMIT - EXTRA_LENGTHS + 1) {
        litLen = EXTRA_LIT_LENGTHS[litLen - (LIT_LENGTH_LIMIT - EXTRA_LENGTHS + 1)];
      }
      let zeroLenRet = arithDecompress(zeros, ab);
      if (arithWasEscaped(zeroLenRet)) {
        const escaped = varBitsGet(vb, ZERO_LENGTH_BITS);
        arithSetDecompressed(zeroLenRet, escaped, zeros);
        zeroLen = escaped;
      } else {
        zeroLen = zeroLenRet;
      }
      if (zeroLen >= ZERO_LENGTH_LIMIT - EXTRA_LENGTHS + 1) {
        zeroLen = EXTRA_ZERO_LENGTHS[zeroLen - (ZERO_LENGTH_LIMIT - EXTRA_LENGTHS + 1)] + MIN_ZERO_LENGTH - 1;
      } else if (zeroLen) {
        zeroLen += MIN_ZERO_LENGTH - 1;
      }
      if (litLen === 0 && zeroLen === 0) {
        if (++idleIter > 64) {
          throw new Error(`decodeHigh1AfterFirst: stuck at h=${h} w=${w} after ${idleIter} consecutive arith reads with litLen=0/zeroLen=0 \u2014 bitstream likely off-corpus. Encoding=${encWidth}x${encHeight}.`);
        }
      } else {
        idleIter = 0;
      }
      while (litLen > 0) {
        if (w <= 1) {
          if (w) {
            let context = (radabs(prev * 2) + radabs(aboveLeft) + radabs(above) | 0) / 4 | 0;
            context = getBitLevel(context);
            let cur = arithDecompress(a[context], ab);
            if (arithWasEscaped(cur)) {
              const escaped = arithBitsGetValue(ab, num);
              arithSetDecompressed(cur, escaped, a[context]);
              cur = escaped;
            }
            if (cur) {
              const v = -varBitsGet1(vb) | 0;
              cur = (cur ^ v) - v;
              cur = cur * qlevel | 0;
            }
            outp[outOffset++] = cur;
            --litLen;
          }
          if (--h === 0) return;
          w = encWidth;
          outOffset += yadj;
          fromOffset = outOffset - pixelPitch;
          above = outp[fromOffset++];
          aboveLeft = above;
          prev = above;
        } else {
          const aboveRight = outp[fromOffset];
          const __sum4 = radabs(prev) + radabs(aboveLeft) + radabs(above) + radabs(aboveRight) >>> 0;
          let context = __sum4 / 4 >>> 0;
          context = getBitLevel(context);
          let cur = arithDecompress(a[context], ab);
          if (arithWasEscaped(cur)) {
            const escaped = arithBitsGetValue(ab, num);
            arithSetDecompressed(cur, escaped, a[context]);
            cur = escaped;
          }
          if (cur) {
            const v = -varBitsGet1(vb) | 0;
            cur = (cur ^ v) - v;
            cur = cur * qlevel | 0;
          }
          outp[outOffset] = cur;
          aboveLeft = above;
          above = aboveRight;
          prev = cur;
          ++outOffset;
          ++fromOffset;
          --w;
          --litLen;
        }
      }
      while (zeroLen > 0) {
        if (zeroLen >= w) {
          zeroLen -= w;
          fromOffset += w;
          while (w-- > 0) outp[outOffset++] = 0;
          if (--h === 0) return;
          w = encWidth;
          outOffset += yadj;
          fromOffset = outOffset - pixelPitch;
          above = outp[fromOffset++];
          aboveLeft = above;
          prev = above;
        } else {
          w -= zeroLen;
          fromOffset += zeroLen;
          do {
            outp[outOffset++] = 0;
          } while (--zeroLen > 0);
          prev = 0;
          above = outp[fromOffset - 1];
          aboveLeft = outp[fromOffset - 2];
        }
      }
    }
  }
  function planeDecode(buf, srcOffset, output, outOffset, width, height, rowMask) {
    const arithLen = varBitsReadU32LE(buf, srcOffset);
    const varbitsStart = srcOffset + 8 + arithLen;
    const ab = arithBitOpen(buf, srcOffset + 8);
    const vb = varBitsOpen(buf, varbitsStart);
    decodeLow(ab, vb, output, outOffset, width * 16, width >> 4, height >> 4);
    decodeHigh1(ab, vb, output, outOffset + (width >> 4), width * 16, width >> 4, height >> 4);
    decodeHigh1(ab, vb, output, outOffset + width * 8, width * 16, width >> 4, height >> 4);
    decodeHigh1(ab, vb, output, outOffset + (width >> 4) + width * 8, width * 16, width >> 4, height >> 4);
    decodeHigh1(ab, vb, output, outOffset + (width >> 3), width * 8, width >> 3, height >> 3);
    decodeHigh1(ab, vb, output, outOffset + width * 4, width * 8, width >> 3, height >> 3);
    decodeHigh1(ab, vb, output, outOffset + (width >> 3) + width * 4, width * 8, width >> 3, height >> 3);
    decodeHigh1(ab, vb, output, outOffset + (width >> 2), width * 4, width >> 2, height >> 2);
    decodeHigh1(ab, vb, output, outOffset + width * 2, width * 4, width >> 2, height >> 2);
    decodeHigh1(ab, vb, output, outOffset + (width >> 2) + width * 2, width * 4, width >> 2, height >> 2);
    decodeHigh1(ab, vb, output, outOffset + (width >> 1), width * 2, width >> 1, height >> 1);
    decodeHigh1(ab, vb, output, outOffset + width, width * 2, width >> 1, height >> 1);
    decodeHigh1(ab, vb, output, outOffset + (width >> 1) + width, width * 2, width >> 1, height >> 1);
    if (rowMask) {
      readEscapes(ab, rowMask, height);
    }
    const varbitsLen = varBitsReadU32LE(buf, srcOffset + 4);
    return arithLen + varbitsLen + 8;
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/igc-idwt.js
  var SMALLEST_DWT_ROW = 16;
  var SMALLEST_DWT_COL = 16;
  var FLIPSIZE = 8;
  function roundS16(x) {
    const sign = x >> 31;
    return (x + (32767 ^ sign)) / 65536 | 0;
  }
  var _rowLp = new Int32Array(8);
  var _rowHp = new Int32Array(8);
  var _colLp = new Int32Array((16 + 4) * 4);
  var _colHp = new Int32Array((16 + 5) * 4);
  var _remLp = new Int32Array(4);
  var _remHp = new Int32Array(5);
  function iDWTrow(dest, destPitch, src, srcPitch, width, height, rowMask, startY, subHeight) {
    const halfwidth = width >> 1;
    let outBase = startY * destPitch;
    let linBase = startY * srcPitch;
    let hinBase = startY * srcPitch + halfwidth;
    let maskIdx = startY;
    const lp = _rowLp;
    const hp = _rowHp;
    for (let y = 0; y < subHeight; y++) {
      let next = 1;
      let xoutIdx = outBase;
      let xlinIdx = linBase;
      let xhinIdx = hinBase;
      const linEnd = linBase + halfwidth;
      lp[0 + 1] = src[xlinIdx + 0];
      lp[-1 + 1] = lp[1 + 1] = src[xlinIdx + 1];
      lp[2 + 1] = src[xlinIdx + 2];
      lp[2 + 1 + 1] = src[xlinIdx + 3];
      lp[2 + 1 + 2] = src[xlinIdx + 4];
      lp[2 + 1 + 3] = src[xlinIdx + 5];
      xlinIdx += 6;
      hp[0 + 2] = src[xhinIdx + 0];
      hp[1 + 2] = src[xhinIdx + 1];
      hp[2 + 2] = src[xhinIdx + 2];
      hp[2 + 2 + 1] = src[xhinIdx + 3];
      hp[2 + 2 + 2] = src[xhinIdx + 4];
      hp[2 + 2 + 3] = src[xhinIdx + 5];
      hp[-2 + 2] = hp[1 + 2];
      hp[-1 + 2] = hp[0 + 2];
      xhinIdx += 6;
      const isNonZero = rowMask === null || rowMask[maskIdx];
      let x = halfwidth < 8 ? 0 : (halfwidth - 8) / 4 | 0;
      if (isNonZero) {
        while (x-- > 0) {
          let e1, o1, e2, o2, e3, o3, e4, o4;
          e1 = lp[0 + 1] * 51674 - ((lp[-1 + 1] + lp[1 + 1]) * 2667 | 0) - ((hp[-2 + 2] + hp[1 + 2]) * 1563 | 0) + ((hp[-1 + 2] + hp[0 + 2]) * 24733 | 0);
          o1 = ((lp[0 + 1] + lp[1 + 1]) * 27400 | 0) - ((lp[-1 + 1] + lp[2 + 1]) * 4230 | 0) - (hp[0 + 2] * 55882 | 0) - ((hp[-2 + 2] + hp[2 + 2]) * 2479 | 0) + ((hp[-1 + 2] + hp[1 + 2]) * 7250 | 0);
          e2 = lp[0 + 1 + 1] * 51674 - ((lp[-1 + 1 + 1] + lp[1 + 1 + 1]) * 2667 | 0) - ((hp[-2 + 2 + 1] + hp[1 + 2 + 1]) * 1563 | 0) + ((hp[-1 + 2 + 1] + hp[0 + 2 + 1]) * 24733 | 0);
          o2 = ((lp[0 + 1 + 1] + lp[1 + 1 + 1]) * 27400 | 0) - ((lp[-1 + 1 + 1] + lp[2 + 1 + 1]) * 4230 | 0) - (hp[0 + 2 + 1] * 55882 | 0) - ((hp[-2 + 2 + 1] + hp[2 + 2 + 1]) * 2479 | 0) + ((hp[-1 + 2 + 1] + hp[1 + 2 + 1]) * 7250 | 0);
          e3 = lp[0 + 1 + 2] * 51674 - ((lp[-1 + 1 + 2] + lp[1 + 1 + 2]) * 2667 | 0) - ((hp[-2 + 2 + 2] + hp[1 + 2 + 2]) * 1563 | 0) + ((hp[-1 + 2 + 2] + hp[0 + 2 + 2]) * 24733 | 0);
          o3 = ((lp[0 + 1 + 2] + lp[1 + 1 + 2]) * 27400 | 0) - ((lp[-1 + 1 + 2] + lp[2 + 1 + 2]) * 4230 | 0) - (hp[0 + 2 + 2] * 55882 | 0) - ((hp[-2 + 2 + 2] + hp[2 + 2 + 2]) * 2479 | 0) + ((hp[-1 + 2 + 2] + hp[1 + 2 + 2]) * 7250 | 0);
          e4 = lp[0 + 1 + 3] * 51674 - ((lp[-1 + 1 + 3] + lp[1 + 1 + 3]) * 2667 | 0) - ((hp[-2 + 2 + 3] + hp[1 + 2 + 3]) * 1563 | 0) + ((hp[-1 + 2 + 3] + hp[0 + 2 + 3]) * 24733 | 0);
          o4 = ((lp[0 + 1 + 3] + lp[1 + 1 + 3]) * 27400 | 0) - ((lp[-1 + 1 + 3] + lp[2 + 1 + 3]) * 4230 | 0) - (hp[0 + 2 + 3] * 55882 | 0) - ((hp[-2 + 2 + 3] + hp[2 + 2 + 3]) * 2479 | 0) + ((hp[-1 + 2 + 3] + hp[1 + 2 + 3]) * 7250 | 0);
          e1 = roundS16(e1);
          o1 = roundS16(o1);
          e2 = roundS16(e2);
          o2 = roundS16(o2);
          e3 = roundS16(e3);
          o3 = roundS16(o3);
          e4 = roundS16(e4);
          o4 = roundS16(o4);
          dest[xoutIdx + 0] = e1;
          dest[xoutIdx + 1] = o1;
          dest[xoutIdx + 2] = e2;
          dest[xoutIdx + 3] = o2;
          dest[xoutIdx + 4] = e3;
          dest[xoutIdx + 5] = o3;
          dest[xoutIdx + 6] = e4;
          dest[xoutIdx + 7] = o4;
          xoutIdx += 8;
          lp[0] = lp[4];
          lp[1] = lp[5];
          lp[2] = lp[6];
          lp[3] = src[xlinIdx + 0];
          lp[4] = src[xlinIdx + 1];
          lp[5] = src[xlinIdx + 2];
          lp[6] = src[xlinIdx + 3];
          hp[0] = hp[4];
          hp[1] = hp[5];
          hp[2] = hp[6];
          hp[3] = hp[7];
          hp[4] = src[xhinIdx + 0];
          hp[5] = src[xhinIdx + 1];
          hp[6] = src[xhinIdx + 2];
          hp[7] = src[xhinIdx + 3];
          xlinIdx += 4;
          xhinIdx += 4;
        }
        let xRem = halfwidth < 8 ? halfwidth : (halfwidth & 3) + 8;
        while (xRem-- > 0) {
          if (xlinIdx === linEnd) {
            xlinIdx -= next;
            xhinIdx -= next + next;
            next = -next;
          }
          let e = lp[0 + 1] * 51674 - ((lp[-1 + 1] + lp[1 + 1]) * 2667 | 0) - ((hp[-2 + 2] + hp[1 + 2]) * 1563 | 0) + ((hp[-1 + 2] + hp[0 + 2]) * 24733 | 0);
          let o = ((lp[0 + 1] + lp[1 + 1]) * 27400 | 0) - ((lp[-1 + 1] + lp[2 + 1]) * 4230 | 0) - (hp[0 + 2] * 55882 | 0) - ((hp[-2 + 2] + hp[2 + 2]) * 2479 | 0) + ((hp[-1 + 2] + hp[1 + 2]) * 7250 | 0);
          e = roundS16(e);
          o = roundS16(o);
          dest[xoutIdx + 0] = e;
          dest[xoutIdx + 1] = o;
          xoutIdx += 2;
          lp[0] = lp[1];
          lp[1] = lp[2];
          lp[2] = lp[3];
          lp[3] = lp[4];
          lp[4] = lp[5];
          lp[5] = lp[6];
          lp[6] = src[xlinIdx];
          hp[0] = hp[1];
          hp[1] = hp[2];
          hp[2] = hp[3];
          hp[3] = hp[4];
          hp[4] = hp[5];
          hp[5] = hp[6];
          hp[6] = hp[7];
          hp[7] = src[xhinIdx];
          xlinIdx += next;
          xhinIdx += next;
        }
      } else {
        while (x-- > 0) {
          let e1, o1, e2, o2, e3, o3, e4, o4;
          e1 = lp[0 + 1] * 51674 - ((lp[-1 + 1] + lp[1 + 1]) * 2667 | 0);
          o1 = ((lp[0 + 1] + lp[1 + 1]) * 27400 | 0) - ((lp[-1 + 1] + lp[2 + 1]) * 4230 | 0);
          e2 = lp[0 + 1 + 1] * 51674 - ((lp[-1 + 1 + 1] + lp[1 + 1 + 1]) * 2667 | 0);
          o2 = ((lp[0 + 1 + 1] + lp[1 + 1 + 1]) * 27400 | 0) - ((lp[-1 + 1 + 1] + lp[2 + 1 + 1]) * 4230 | 0);
          e3 = lp[0 + 1 + 2] * 51674 - ((lp[-1 + 1 + 2] + lp[1 + 1 + 2]) * 2667 | 0);
          o3 = ((lp[0 + 1 + 2] + lp[1 + 1 + 2]) * 27400 | 0) - ((lp[-1 + 1 + 2] + lp[2 + 1 + 2]) * 4230 | 0);
          e4 = lp[0 + 1 + 3] * 51674 - ((lp[-1 + 1 + 3] + lp[1 + 1 + 3]) * 2667 | 0);
          o4 = ((lp[0 + 1 + 3] + lp[1 + 1 + 3]) * 27400 | 0) - ((lp[-1 + 1 + 3] + lp[2 + 1 + 3]) * 4230 | 0);
          e1 = roundS16(e1);
          o1 = roundS16(o1);
          e2 = roundS16(e2);
          o2 = roundS16(o2);
          e3 = roundS16(e3);
          o3 = roundS16(o3);
          e4 = roundS16(e4);
          o4 = roundS16(o4);
          dest[xoutIdx + 0] = e1;
          dest[xoutIdx + 1] = o1;
          dest[xoutIdx + 2] = e2;
          dest[xoutIdx + 3] = o2;
          dest[xoutIdx + 4] = e3;
          dest[xoutIdx + 5] = o3;
          dest[xoutIdx + 6] = e4;
          dest[xoutIdx + 7] = o4;
          xoutIdx += 8;
          lp[0] = lp[4];
          lp[1] = lp[5];
          lp[2] = lp[6];
          lp[3] = src[xlinIdx + 0];
          lp[4] = src[xlinIdx + 1];
          lp[5] = src[xlinIdx + 2];
          lp[6] = src[xlinIdx + 3];
          xlinIdx += 4;
        }
        let xRem = halfwidth < 8 ? halfwidth : (halfwidth & 3) + 8;
        while (xRem-- > 0) {
          if (xlinIdx === linEnd) {
            xlinIdx -= 1;
            next = -1;
          }
          let e = lp[0 + 1] * 51674 - ((lp[-1 + 1] + lp[1 + 1]) * 2667 | 0);
          let o = ((lp[0 + 1] + lp[1 + 1]) * 27400 | 0) - ((lp[-1 + 1] + lp[2 + 1]) * 4230 | 0);
          e = roundS16(e);
          o = roundS16(o);
          dest[xoutIdx + 0] = e;
          dest[xoutIdx + 1] = o;
          xoutIdx += 2;
          lp[0] = lp[1];
          lp[1] = lp[2];
          lp[2] = lp[3];
          lp[3] = lp[4];
          lp[4] = lp[5];
          lp[5] = lp[6];
          lp[6] = src[xlinIdx];
          xlinIdx += next;
        }
      }
      outBase += destPitch;
      linBase += srcPitch;
      hinBase += srcPitch;
      ++maskIdx;
    }
  }
  function iDWTcol(dest, destPitch, src, srcPitch, width, height, startY, subHeight) {
    const halfheight = subHeight >> 1;
    let outBase = startY * destPitch;
    let linBase = 0;
    let hinBase = srcPitch;
    const lendCol0 = srcPitch * height;
    const ppitch2 = srcPitch * 2;
    if (startY) {
      linBase += ((startY / 2 | 0) - 1) * ppitch2;
      hinBase += ((startY / 2 | 0) - 2) * ppitch2;
    }
    let colsBase = 0;
    const groupCount = width / 4 | 0;
    for (let g = 0; g < groupCount; g++) {
      let next = ppitch2;
      let youtBase = outBase + colsBase;
      let ylinBase = linBase + colsBase;
      let yhinBase = hinBase + colsBase;
      const lend = lendCol0 + colsBase;
      const lp = _colLp;
      const hp = _colHp;
      if (startY) {
        for (let k = 0; k < 4; k++) lp[(-1 + 1) * 4 + k] = src[ylinBase + k];
        ylinBase += next;
        for (let k = 0; k < 4; k++) lp[(0 + 1) * 4 + k] = src[ylinBase + k];
        ylinBase += next;
        for (let k = 0; k < 4; k++) lp[(1 + 1) * 4 + k] = src[ylinBase + k];
        ylinBase += next;
        for (let k = 0; k < 4; k++) lp[(2 + 1) * 4 + k] = src[ylinBase + k];
        ylinBase += next;
        for (let k = 0; k < 4; k++) hp[(-2 + 2) * 4 + k] = src[yhinBase + k];
        yhinBase += next;
        for (let k = 0; k < 4; k++) hp[(-1 + 2) * 4 + k] = src[yhinBase + k];
        yhinBase += next;
        for (let k = 0; k < 4; k++) hp[(0 + 2) * 4 + k] = src[yhinBase + k];
        yhinBase += next;
        for (let k = 0; k < 4; k++) hp[(1 + 2) * 4 + k] = src[yhinBase + k];
        yhinBase += next;
        for (let k = 0; k < 4; k++) hp[(2 + 2) * 4 + k] = src[yhinBase + k];
        yhinBase += next;
      } else {
        for (let k = 0; k < 4; k++) lp[(0 + 1) * 4 + k] = src[ylinBase + k];
        ylinBase += next;
        for (let k = 0; k < 4; k++) {
          const v = src[ylinBase + k];
          lp[(-1 + 1) * 4 + k] = v;
          lp[(1 + 1) * 4 + k] = v;
        }
        ylinBase += next;
        for (let k = 0; k < 4; k++) lp[(2 + 1) * 4 + k] = src[ylinBase + k];
        ylinBase += next;
        for (let k = 0; k < 4; k++) {
          const v = src[yhinBase + k];
          hp[(-1 + 2) * 4 + k] = v;
          hp[(0 + 2) * 4 + k] = v;
        }
        yhinBase += next;
        for (let k = 0; k < 4; k++) {
          const v = src[yhinBase + k];
          hp[(-2 + 2) * 4 + k] = v;
          hp[(1 + 2) * 4 + k] = v;
        }
        yhinBase += next;
        for (let k = 0; k < 4; k++) hp[(2 + 2) * 4 + k] = src[yhinBase + k];
        yhinBase += next;
      }
      let lpOff = 0;
      let hpOff = 0;
      for (let y = 0; y < halfheight; y++) {
        if (ylinBase === lend) {
          ylinBase -= next;
          yhinBase -= next + next;
          next = -next;
        }
        const lpC = lpOff;
        const hpC = hpOff;
        let e1, e2, e3, e4, o1, o2, o3, o4;
        for (let k = 0; k < 4; k++) {
          const lpm1 = lp[(lpC + 0) * 4 + k];
          const lp0 = lp[(lpC + 1) * 4 + k];
          const lp1 = lp[(lpC + 2) * 4 + k];
          const lp2 = lp[(lpC + 3) * 4 + k];
          const hpm2 = hp[(hpC + 0) * 4 + k];
          const hpm1 = hp[(hpC + 1) * 4 + k];
          const hp0 = hp[(hpC + 2) * 4 + k];
          const hp1 = hp[(hpC + 3) * 4 + k];
          const hp2 = hp[(hpC + 4) * 4 + k];
          const e = lp0 * 51674 - ((lpm1 + lp1) * 2667 | 0) - ((hpm2 + hp1) * 1563 | 0) + ((hpm1 + hp0) * 24733 | 0);
          const o = ((lp0 + lp1) * 27400 | 0) - ((lpm1 + lp2) * 4230 | 0) - (hp0 * 55882 | 0) - ((hpm2 + hp2) * 2479 | 0) + ((hpm1 + hp1) * 7250 | 0);
          const er = roundS16(e);
          const or = roundS16(o);
          if (k === 0) {
            e1 = er;
            o1 = or;
          } else if (k === 1) {
            e2 = er;
            o2 = or;
          } else if (k === 2) {
            e3 = er;
            o3 = or;
          } else {
            e4 = er;
            o4 = or;
          }
        }
        dest[youtBase + 0] = e1;
        dest[youtBase + 1] = e2;
        dest[youtBase + 2] = e3;
        dest[youtBase + 3] = e4;
        dest[youtBase + destPitch + 0] = o1;
        dest[youtBase + destPitch + 1] = o2;
        dest[youtBase + destPitch + 2] = o3;
        dest[youtBase + destPitch + 3] = o4;
        youtBase += destPitch + destPitch;
        ++lpOff;
        ++hpOff;
        if (lpOff + 3 === 16 + 4) {
          for (let k = 0; k < 4; k++) lp[0 * 4 + k] = lp[(lpOff + 1) * 4 + k];
          for (let k = 0; k < 4; k++) lp[1 * 4 + k] = lp[(lpOff + 2) * 4 + k];
          for (let k = 0; k < 4; k++) lp[2 * 4 + k] = lp[(lpOff + 3) * 4 + k];
          for (let k = 0; k < 4; k++) hp[0 * 4 + k] = hp[(hpOff + 1) * 4 + k];
          for (let k = 0; k < 4; k++) hp[1 * 4 + k] = hp[(hpOff + 2) * 4 + k];
          for (let k = 0; k < 4; k++) hp[2 * 4 + k] = hp[(hpOff + 3) * 4 + k];
          for (let k = 0; k < 4; k++) hp[3 * 4 + k] = hp[(hpOff + 4) * 4 + k];
          lpOff = 0;
          hpOff = 0;
        }
        for (let k = 0; k < 4; k++) lp[(lpOff + 3) * 4 + k] = src[ylinBase + k];
        for (let k = 0; k < 4; k++) hp[(hpOff + 4) * 4 + k] = src[yhinBase + k];
        ylinBase += next;
        yhinBase += next;
      }
      colsBase += 4;
    }
    const remCols = width & 3;
    for (let g = 0; g < remCols; g++) {
      let next = ppitch2;
      let youtBase = outBase + colsBase;
      let ylinBase = linBase + colsBase;
      let yhinBase = hinBase + colsBase;
      const lend = lendCol0 + colsBase;
      const lp = _remLp;
      const hp = _remHp;
      if (startY) {
        lp[-1 + 1] = src[ylinBase];
        ylinBase += next;
        lp[0 + 1] = src[ylinBase];
        ylinBase += next;
        lp[1 + 1] = src[ylinBase];
        ylinBase += next;
        lp[2 + 1] = src[ylinBase];
        ylinBase += next;
        hp[-2 + 2] = src[yhinBase];
        yhinBase += next;
        hp[-1 + 2] = src[yhinBase];
        yhinBase += next;
        hp[0 + 2] = src[yhinBase];
        yhinBase += next;
        hp[1 + 2] = src[yhinBase];
        yhinBase += next;
        hp[2 + 2] = src[yhinBase];
        yhinBase += next;
      } else {
        lp[0 + 1] = src[ylinBase];
        ylinBase += next;
        lp[-1 + 1] = lp[1 + 1] = src[ylinBase];
        ylinBase += next;
        lp[2 + 1] = src[ylinBase];
        ylinBase += next;
        hp[-1 + 2] = hp[0 + 2] = src[yhinBase];
        yhinBase += next;
        hp[-2 + 2] = hp[1 + 2] = src[yhinBase];
        yhinBase += next;
        hp[2 + 2] = src[yhinBase];
        yhinBase += next;
      }
      for (let y = 0; y < halfheight; y++) {
        if (ylinBase === lend) {
          ylinBase -= next;
          yhinBase -= next + next;
          next = -next;
        }
        const e = lp[0 + 1] * 51674 - ((lp[-1 + 1] + lp[1 + 1]) * 2667 | 0) - ((hp[-2 + 2] + hp[1 + 2]) * 1563 | 0) + ((hp[-1 + 2] + hp[0 + 2]) * 24733 | 0);
        const o = ((lp[0 + 1] + lp[1 + 1]) * 27400 | 0) - ((lp[-1 + 1] + lp[2 + 1]) * 4230 | 0) - (hp[0 + 2] * 55882 | 0) - ((hp[-2 + 2] + hp[2 + 2]) * 2479 | 0) + ((hp[-1 + 2] + hp[1 + 2]) * 7250 | 0);
        dest[youtBase] = roundS16(e);
        dest[youtBase + destPitch] = roundS16(o);
        youtBase += destPitch + destPitch;
        lp[0] = lp[1];
        lp[1] = lp[2];
        lp[2] = lp[3];
        lp[3] = src[ylinBase];
        hp[0] = hp[1];
        hp[1] = hp[2];
        hp[2] = hp[3];
        hp[3] = hp[4];
        hp[4] = src[yhinBase];
        ylinBase += next;
        yhinBase += next;
      }
      colsBase += 1;
    }
  }
  function iHarrrow(dest, destPitch, src, srcPitch, width, height, rowMask, startY, subHeight) {
    const halfwidth = width >> 1;
    let outBase = startY * destPitch;
    let linBase = startY * srcPitch;
    let hinBase = startY * srcPitch + halfwidth;
    let maskIdx = startY;
    for (let y = 0; y < subHeight; y++) {
      let xoutIdx = outBase;
      let xlinIdx = linBase;
      let xhinIdx = hinBase;
      const isNonZero = rowMask === null || rowMask[maskIdx];
      if (isNonZero) {
        for (let x = 0; x < halfwidth; x++) {
          const lv = src[xlinIdx];
          const hv = src[xhinIdx];
          let e = lv * 2 + hv | 0;
          let o = lv * 2 - hv | 0;
          e = (e + (1 ^ e >> 31)) / 2 | 0;
          o = (o + (1 ^ o >> 31)) / 2 | 0;
          dest[xoutIdx + 0] = e;
          dest[xoutIdx + 1] = o;
          xoutIdx += 2;
          xlinIdx += 1;
          xhinIdx += 1;
        }
      } else {
        for (let x = 0; x < halfwidth; x++) {
          const e = src[xlinIdx];
          dest[xoutIdx + 0] = e;
          dest[xoutIdx + 1] = e;
          xoutIdx += 2;
          xlinIdx += 1;
        }
      }
      outBase += destPitch;
      linBase += srcPitch;
      hinBase += srcPitch;
      ++maskIdx;
    }
  }
  function iHarrcol(dest, destPitch, src, srcPitch, width, height, startY, subHeight) {
    const halfheight = subHeight >> 1;
    let outBase = startY * destPitch;
    let linBase = 0;
    let hinBase = srcPitch;
    const ppitch2 = srcPitch * 2;
    if (startY) {
      linBase += (startY / 2 | 0) * ppitch2;
      hinBase += (startY / 2 | 0) * ppitch2;
    }
    for (let x = 0; x < width; x++) {
      let youtBase = outBase + x;
      let ylinBase = linBase + x;
      let yhinBase = hinBase + x;
      for (let y = 0; y < halfheight; y++) {
        const lv = src[ylinBase];
        const hv = src[yhinBase];
        let e = lv * 2 + hv | 0;
        let o = lv * 2 - hv | 0;
        e = (e + (1 ^ e >> 31)) / 2 | 0;
        o = (o + (1 ^ o >> 31)) / 2 | 0;
        dest[youtBase] = e;
        dest[youtBase + destPitch] = o;
        youtBase += destPitch + destPitch;
        ylinBase += ppitch2;
        yhinBase += ppitch2;
      }
    }
  }
  function iDWT2D(output, pitch, width, height, rowMask, temp) {
    const rowFn = width >= SMALLEST_DWT_ROW ? iDWTrow : iHarrrow;
    const colFn = height >= SMALLEST_DWT_COL ? iDWTcol : iHarrcol;
    let ry = height <= FLIPSIZE + 4 + 4 ? height : FLIPSIZE + 4;
    let rh = height - ry;
    let cy = 0;
    let ch = height;
    rowFn(temp, pitch, output, pitch, width, height, rowMask, 0, ry);
    do {
      let next = ch <= FLIPSIZE + 4 ? ch : FLIPSIZE;
      colFn(output, pitch, temp, pitch, width, height, cy, next);
      cy += next;
      ch -= next;
      if (rh) {
        next = rh <= FLIPSIZE + 4 ? rh : FLIPSIZE;
        rowFn(temp, pitch, output, pitch, width, height, rowMask, ry, next);
        ry += next;
        rh -= next;
      }
    } while (ch);
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/igc-pipeline.js
  function runIGCPipeline(src, width, height, alpha, planeDecode2, iDWT2D2, yuvToRGB2) {
    const planeCount = alpha ? 4 : 3;
    const planes = new Array(4);
    for (let i = 0; i < 4; i++) planes[i] = new Int16Array(width * height);
    const rowMask = new Uint8Array(height);
    const temp = new Int16Array(width * height);
    let cursor = 4;
    for (let p = 0; p < planeCount; p++) {
      const consumed = planeDecode2(
        src,
        cursor,
        planes[p],
        0,
        width,
        height,
        p === 0 ? rowMask : null
      );
      cursor += consumed;
      iDWT2D2(planes[p], width * 8, width >> 3, height >> 3, null, temp);
      iDWT2D2(planes[p], width * 4, width >> 2, height >> 2, null, temp);
      iDWT2D2(planes[p], width * 2, width >> 1, height >> 1, null, temp);
      iDWT2D2(planes[p], width, width, height, p === 0 ? rowMask : null, temp);
    }
    if (!alpha) {
      for (let i = 0; i < width * height; i++) planes[3][i] = 255;
    }
    return yuvToRGB2(planes[0], planes[1], planes[2], planes[3], width, height);
  }
  function decodeIGCPipeline(src, width, height, alpha) {
    return runIGCPipeline(src, width, height, alpha, planeDecode, iDWT2D, yuvToRGB);
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/igc-arith.js
  var IGC_ARITH_VERIFY = typeof process !== "undefined" && !!process.env && process.env.IGC_ARITH_VERIFY === "1";
  var __arithCall = 0;
  function __arithVerify(site, fast, ref) {
    __arithCall++;
    if (ref !== fast) {
      throw new Error(
        `[IGC_ARITH_VERIFY] ${site} divergence at call #${__arithCall}: f64=${fast} bigint=${ref}`
      );
    }
  }
  var BR4 = new Uint8Array([0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15]);
  var BR3 = new Uint8Array([0, 4, 2, 6, 1, 5, 3, 7]);
  var BR8 = (() => {
    const t = new Uint8Array(256);
    for (let i = 0; i < 256; i++) {
      t[i] = BR4[i & 15] << 4 | BR4[i >>> 4 & 15];
    }
    return t;
  })();
  function arithBitOpen(buf, offset) {
    const b0 = buf[offset] | 0, b1 = buf[offset + 1] | 0, b2 = buf[offset + 2] | 0, b3 = buf[offset + 3] | 0;
    const dword = (b0 | b1 << 8 | b2 << 16 | b3 << 24) >>> 0;
    const topBit = dword >>> 31 & 1;
    const lo31 = dword & 2147483647;
    let t = BR4[lo31 >>> 4 & 15];
    t |= BR4[lo31 & 15] << 4;
    t = t << 4 >>> 0 | BR4[lo31 >>> 8 & 15];
    t = t << 4 >>> 0 | BR4[lo31 >>> 12 & 15];
    t = t << 4 >>> 0 | BR4[lo31 >>> 16 & 15];
    t = t << 4 >>> 0 | BR4[lo31 >>> 20 & 15];
    t = t << 4 >>> 0 | BR4[lo31 >>> 24 & 15];
    t = t << 3 >>> 0 | BR3[lo31 >>> 28 & 7];
    return {
      buf,
      ptr: offset + 4 | 0,
      accum: topBit,
      bitsLeft: 1,
      high: 2147483647,
      low: 0,
      target: t >>> 0
    };
  }
  function arithPullBits(ab, n) {
    let bitsLeft = ab.bitsLeft | 0;
    let accum = ab.accum >>> 0;
    let raw;
    if (bitsLeft < n) {
      const buf = ab.buf;
      const p = ab.ptr | 0;
      const refill = (buf[p] | buf[p + 1] << 8 | buf[p + 2] << 16 | buf[p + 3] << 24) >>> 0;
      const eax = bitsLeft === 0 ? refill : (refill << bitsLeft | accum) >>> 0;
      ab.accum = refill >>> n - bitsLeft >>> 0;
      ab.bitsLeft = bitsLeft + 32 - n;
      ab.ptr = p + 4 | 0;
      raw = eax & (1 << n) - 1;
    } else {
      raw = accum & (1 << n) - 1;
      ab.accum = accum >>> n >>> 0;
      ab.bitsLeft = bitsLeft - n;
    }
    return n === 8 ? BR8[raw] : n === 4 ? BR4[raw] : raw;
  }
  function arithRenorm(ab) {
    let h = ab.high >>> 0;
    let l = ab.low >>> 0;
    let t = ab.target >>> 0;
    let xh = (l ^ h) >>> 0;
    if ((xh & 1073741824) === 0) {
      if ((xh & 2139095040) === 0) {
        do {
          h = (h << 8 | 255) >>> 0 & 2147483647;
          l = l << 8 >>> 0 & 2147483647;
          const b = arithPullBits(ab, 8);
          t = (t << 8 | b) >>> 0 & 2147483647;
          xh = (l ^ h) >>> 0;
        } while ((xh & 2139095040) === 0);
      }
      if ((xh & 2013265920) === 0) {
        h = (h << 4 | 15) >>> 0 & 2147483647;
        l = l << 4 >>> 0 & 2147483647;
        const n = arithPullBits(ab, 4);
        t = (t << 4 | n) >>> 0 & 2147483647;
        xh = (l ^ h) >>> 0;
      }
      if ((xh & 1073741824) === 0) {
        do {
          h = (h << 1 | 1) >>> 0 & 2147483647;
          l = l << 1 >>> 0 & 2147483647;
          const bit = arithPullBits(ab, 1);
          t = (t << 1 | bit) >>> 0 & 2147483647;
          xh = (l ^ h) >>> 0;
        } while ((xh & 1073741824) === 0);
      }
    }
    if ((l & 536870912) !== 0) {
      while (true) {
        if ((h & 536870912) !== 0) break;
        l = (l & 536870911) << 1 >>> 0 & 2147483647;
        h = (h << 1 | 1073741825) >>> 0 & 2147483647;
        t = (t ^ 536870912) >>> 0;
        const bit = arithPullBits(ab, 1);
        t = (t << 1 | bit) >>> 0 & 2147483647;
        if ((l & 536870912) === 0) break;
      }
    }
    ab.high = h;
    ab.low = l;
    ab.target = t;
  }
  function arithBitsGet(ab, scale) {
    const range = ab.high - ab.low + 1 >>> 0;
    const tNorm = ab.target - ab.low + 1 >>> 0;
    const v = (tNorm * scale - 1) / range | 0;
    if (IGC_ARITH_VERIFY) __arithVerify("Get", v, Number((BigInt(tNorm) * BigInt(scale) - 1n) / BigInt(range)) | 0);
    return v >= scale ? scale - 1 : v;
  }
  function arithBitsRemove(ab, lo, count, scale) {
    const range = ab.high - ab.low + 1 >>> 0;
    const num1 = Math.floor(range * (lo + count) / scale);
    const num2 = Math.floor(range * lo / scale);
    if (IGC_ARITH_VERIFY) {
      const sBig = BigInt(scale);
      __arithVerify("Remove.num1", num1, Number(BigInt(range) * BigInt(lo + count) / sBig));
      __arithVerify("Remove.num2", num2, Number(BigInt(range) * BigInt(lo) / sBig));
    }
    const oldLow = ab.low >>> 0;
    ab.high = oldLow + num1 - 1 >>> 0;
    ab.low = oldLow + num2 >>> 0;
    arithRenorm(ab);
  }
  function arithBitsGetValue(ab, scale) {
    const range = ab.high - ab.low + 1 >>> 0;
    const tNorm = ab.target - ab.low + 1 >>> 0;
    let v = (tNorm * scale - 1) / range | 0;
    if (IGC_ARITH_VERIFY) __arithVerify("GetValue", v, Number((BigInt(tNorm) * BigInt(scale) - 1n) / BigInt(range)) | 0);
    if (v >= scale) v = scale - 1;
    arithBitsRemove(ab, v, 1, scale);
    return v;
  }
  var ARITH_RESCALE_TRIGGER = 16384;
  function arithInitBands(a, uniqueValuesPlus1) {
    if (uniqueValuesPlus1 < 6) {
      a.bucketSize = 0;
      a.shiftDepth = 15;
      a.bandBoundary = 0;
      return;
    }
    let bestShift2 = 0;
    let bestLeftover = 4294967295 >>> 0;
    for (let cl = 0; cl < 16; cl++) {
      const bucketSize = 1 << cl;
      let nbBuckets = ((bucketSize + uniqueValuesPlus1 - 1) / bucketSize | 0) >>> 0;
      if (nbBuckets > 16) nbBuckets = 16;
      let leftover = uniqueValuesPlus1 - (nbBuckets - 1) * bucketSize >>> 0;
      if (leftover < bucketSize) leftover = bucketSize >>> 0;
      if (leftover < bestLeftover) {
        bestShift2 = cl;
        bestLeftover = leftover;
      }
      if (bucketSize > uniqueValuesPlus1) break;
    }
    a.bucketSize = 1 << bestShift2 & 65535;
    a.shiftDepth = bestShift2 & 255;
    a.bandBoundary = 15 * a.bucketSize & 65535;
  }
  function arithUpdate(a, idx, magic) {
    const lo = magic & 65535;
    const hi = magic >>> 16 & 65535;
    if (idx >= a.bandBoundary) {
      a.cumCounts[15] = a.cumCounts[15] + lo & 65535;
      a.singleCounts[idx] = a.singleCounts[idx] + lo & 65535;
      return;
    }
    let d = idx >>> a.shiftDepth;
    if (d & 1) {
      a.cumCounts[d] = a.cumCounts[d] + lo & 65535;
      d++;
    }
    d >>>= 1;
    if (d <= 7) {
      const umagic = magic >>> 0;
      for (let k = d; k <= 7; k++) {
        const j = k * 2 | 0;
        const oldDword = a.cumCounts[j + 1] * 65536 + a.cumCounts[j] >>> 0;
        const newDword = oldDword + umagic >>> 0;
        a.cumCounts[j] = newDword & 65535;
        a.cumCounts[j + 1] = newDword >>> 16 & 65535;
      }
    }
    a.singleCounts[idx] = a.singleCounts[idx] + lo & 65535;
  }
  function arithSearch(a, offset) {
    const cc = a.cumCounts;
    let bucket = 0;
    let lo = 0;
    if (offset >= cc[7]) {
      lo = cc[7];
      bucket = 8;
    }
    if (offset >= cc[bucket + 3]) {
      lo = cc[bucket + 3];
      bucket += 4;
    }
    if (offset >= cc[bucket + 1]) {
      lo = cc[bucket + 1];
      bucket += 2;
    }
    if (offset >= cc[bucket]) {
      lo = cc[bucket];
      bucket += 1;
    }
    for (let i = bucket; i < 16; i++) {
      cc[i] = cc[i] + 1 & 65535;
    }
    const baseIdx = bucket * a.bucketSize | 0;
    let idx = baseIdx;
    let cumLo = lo;
    const sc = a.singleCounts;
    const end = Math.min(sc.length, a.uniqueCount + 1 | 0);
    while (idx < end) {
      const high = cumLo + sc[idx] & 65535;
      if (offset < high) {
        return [idx, cumLo];
      }
      cumLo = high;
      idx++;
    }
    const fallback = Math.min(Math.max(idx - 1, 0), Math.max(a.uniqueCount, 0));
    return [fallback, cumLo];
  }
  function arithReEmitCumFromScratch(a, scratch) {
    if (a.singlesLength !== a.uniqueCount && a.singleCounts[0] === 0) {
      a.singleCounts[0] = 2;
      const bucket0 = 0 >= a.bandBoundary ? 15 : 0;
      scratch[bucket0] = scratch[bucket0] + 2 >>> 0;
    }
    let cum = 0;
    for (let k = 0; k < 16; k++) {
      cum = cum + scratch[k] & 65535;
      a.cumCounts[k] = cum;
    }
  }
  function arithRescale(a) {
    arithInitBands(a, a.singlesLength + 1 | 0);
    const scratch = new Uint32Array(16);
    a.singleCounts[0] = a.singleCounts[0] >>> 1 & 65535;
    const bucket0 = 0 >= a.bandBoundary ? 15 : 0;
    scratch[bucket0] = a.singleCounts[0] >>> 0;
    let max = 0;
    let maxPos = 0;
    let i = 1;
    while (i <= a.singlesLength) {
      while (a.singleCounts[i] <= 1) {
        if (i >= a.singlesLength) {
          a.singleCounts[i] = 0;
          a.singlesLength = a.singlesLength - 1 | 0;
          break;
        }
        a.singleCounts[i] = a.singleCounts[a.singlesLength];
        a.singleCounts[a.singlesLength] = 0;
        a.values[i] = a.values[a.singlesLength];
        a.singlesLength = a.singlesLength - 1 | 0;
      }
      if (i > a.singlesLength) break;
      a.singleCounts[i] = a.singleCounts[i] >>> 1 & 65535;
      const sc = a.singleCounts[i];
      if (sc > max) {
        max = sc;
        maxPos = i;
      }
      const bucket = i >= a.bandBoundary ? 15 : i >>> a.shiftDepth;
      scratch[bucket] = scratch[bucket] + sc >>> 0;
      i++;
    }
    if (max > 0) {
      let target;
      if (a.singlesLength >= a.bandBoundary) {
        target = a.bandBoundary;
      } else {
        target = a.singlesLength >>> a.shiftDepth << a.shiftDepth;
      }
      if (target === 0) target = 1;
      if (maxPos !== target) {
        const oldScTarget = a.singleCounts[target] >>> 0;
        const scMaxPos = a.singleCounts[maxPos] >>> 0;
        const delta = scMaxPos - oldScTarget | 0;
        const bucketTarget = target >= a.bandBoundary ? 15 : target >>> a.shiftDepth;
        const bucketMaxPos = maxPos >= a.bandBoundary ? 15 : maxPos >>> a.shiftDepth;
        scratch[bucketTarget] = scratch[bucketTarget] + delta >>> 0;
        scratch[bucketMaxPos] = scratch[bucketMaxPos] - delta >>> 0;
        a.singleCounts[target] = scMaxPos;
        a.singleCounts[maxPos] = oldScTarget;
        const valTarget = a.values[target];
        a.values[target] = a.values[maxPos];
        a.values[maxPos] = valTarget;
      }
    }
    arithReEmitCumFromScratch(a, scratch);
  }
  var IGC_MAX_ALPHABET = 8192;
  function arithOpen(_maxValue, uniqueValues) {
    if (uniqueValues > IGC_MAX_ALPHABET) {
      throw new Error(`igc arith alphabet ${uniqueValues} exceeds cap ${IGC_MAX_ALPHABET}`);
    }
    const countsSize = uniqueValues + 5 & ~3 | 0;
    const a = {
      cumCounts: new Uint16Array(16),
      singleCounts: new Uint16Array(countsSize),
      values: new Uint16Array(countsSize),
      singlesLength: 0,
      bandBoundary: 0,
      shiftDepth: 0,
      bucketSize: 0,
      uniqueCount: uniqueValues
    };
    arithInitBands(a, uniqueValues + 1 | 0);
    arithUpdate(a, 0, 196611);
    return a;
  }
  function arithMakeEscape(slot) {
    return { __escape: true, slot };
  }
  function arithWasEscaped(ret) {
    return typeof ret === "object";
  }
  function arithSetDecompressed(escapeRet, value, a) {
    a.values[escapeRet.slot] = value;
  }
  function arithDecompress(a, ab) {
    if (a.cumCounts[15] >= ARITH_RESCALE_TRIGGER) {
      arithRescale(a);
    }
    if (globalThis.__igcTrace) {
      const idx = globalThis.__igcTraceIdx | 0;
      const exp = globalThis.__igcTrace[idx];
      if (exp) {
        const errs = [];
        const actH = ab.high >>> 0, actL = ab.low >>> 0, actT = ab.target >>> 0;
        const expH = parseInt(exp.abH, 16), expL = parseInt(exp.abL, 16), expT = parseInt(exp.abT, 16);
        if (actH !== expH) errs.push(`abH 0x${actH.toString(16)} vs 0x${expH.toString(16)}`);
        if (actL !== expL) errs.push(`abL 0x${actL.toString(16)} vs 0x${expL.toString(16)}`);
        if (actT !== expT) errs.push(`abT 0x${actT.toString(16)} vs 0x${expT.toString(16)}`);
        for (let k = 0; k < 16; k++) {
          if (a.cumCounts[k] !== exp.cum[k]) {
            errs.push(`cum[${k}] ${a.cumCounts[k]} vs ${exp.cum[k]}`);
          }
        }
        if (a.singlesLength !== exp.sL) errs.push(`sL ${a.singlesLength} vs ${exp.sL}`);
        if (a.bandBoundary !== exp.bB) errs.push(`bB ${a.bandBoundary} vs ${exp.bB}`);
        if (a.shiftDepth !== exp.sD) errs.push(`sD ${a.shiftDepth} vs ${exp.sD}`);
        if (a.uniqueCount !== exp.uC) errs.push(`uC ${a.uniqueCount} vs ${exp.uC}`);
        if (errs.length > 0) {
          if (!globalThis.__igcDivergences) globalThis.__igcDivergences = [];
          globalThis.__igcDivergences.push({ call: exp.call, errs });
          if (globalThis.__igcDivergences.length === 1 || globalThis.__igcStrictThrow) {
            const e = new Error(`__igcTrace: call ${exp.call} divergence:
  ${errs.join("\n  ")}`);
            e.callIdx = exp.call;
            if (globalThis.__igcStrictThrow) throw e;
            process.stderr.write(`!! First divergence at call ${exp.call}:
  ${errs.join("\n  ")}
`);
          }
        }
      }
      globalThis.__igcTraceIdx = idx + 1;
    }
    const total = a.cumCounts[15];
    const offset = arithBitsGet(ab, total);
    const [refinedIdx, slotLo] = arithSearch(a, offset);
    const slotCount = a.singleCounts[refinedIdx];
    arithBitsRemove(ab, slotLo, slotCount, total);
    a.singleCounts[refinedIdx] = a.singleCounts[refinedIdx] + 1 & 65535;
    if (refinedIdx !== 0) {
      return a.values[refinedIdx];
    }
    a.singlesLength = a.singlesLength + 1 & 65535;
    arithUpdate(a, a.singlesLength, 131074);
    if (a.singlesLength === a.uniqueCount) {
      const sc0 = a.singleCounts[0] | 0;
      const negSc0 = -sc0 & 65535;
      const magicHi = (-sc0 - 1 & 65535) << 16;
      const magic = (magicHi | negSc0) >>> 0;
      arithUpdate(a, 0, magic);
    }
    return arithMakeEscape(a.singlesLength);
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/GrannyTextureIGC.js
  var SMALLEST_DWT_ROW2 = 16;
  var SMALLEST_DWT_COL2 = 16;
  var IGC_MAX_PIXELS = 4096 * 4096;
  var IGC_MAX_PIXELS_PER_BYTE = 4096;
  function decodeIGCTexture(igcImage) {
    const { Width: width, Height: height, Alpha: alpha, ImageData: src } = igcImage;
    if (width * height <= 256) {
      const expected = width * height * 4;
      if (src.byteLength < expected) {
        throw new Error(
          `decodeIGCTexture: small-image fallback expects ${expected} RGBA bytes, got ${src.byteLength} (W=${width}, H=${height})`
        );
      }
      return new Uint8Array(src.buffer, src.byteOffset, expected).slice();
    }
    if (width < SMALLEST_DWT_ROW2 || height < SMALLEST_DWT_COL2 || (width & 15) !== 0 || (height & 15) !== 0) {
      throw new Error(
        `decodeIGCTexture: shouldBink fallback not supported (W=${width}, H=${height}). iRO corpus walker should filter these out.`
      );
    }
    const pixels = width * height;
    if (pixels > IGC_MAX_PIXELS || pixels > src.byteLength * IGC_MAX_PIXELS_PER_BYTE) {
      throw new Error(
        `decodeIGCTexture: ${width}\xD7${height} (${pixels} px) exceeds cap (${IGC_MAX_PIXELS} px / ${IGC_MAX_PIXELS_PER_BYTE}\xD7 of ${src.byteLength} B)`
      );
    }
    return decodeIGCPipeline(src, width, height, alpha);
  }

  // ../../../../../private/tmp/granny-ro-js-gr2-preview/src/GrannyTexture.js
  function walkTextureImages(loaded, options = {}) {
    const maxTextures = options.maxTextures ?? 256;
    const maxImages = options.maxImages ?? 8;
    const maxMips = options.maxMips ?? 32;
    const file = loaded.file;
    const rootTypeTree = parseTypeTree(loaded, file.header.root_type);
    const root = parseObject(loaded, rootTypeTree, file.header.root_object, { maxArrayRefs: maxTextures });
    const texField = root.Textures;
    if (!texField || !texField.reference_type) return [];
    const textureType = texField.reference_type;
    const textureRefs = texField.element_refs ?? [];
    if (textureRefs.length === 0) return [];
    const texMembers = parseTypeTree(loaded, [textureType.section, textureType.offset]);
    const records = [];
    const texCount = textureRefs.length < maxTextures ? textureRefs.length : maxTextures;
    for (let ti = 0; ti < texCount; ti++) {
      const texRef = textureRefs[ti];
      if (!texRef) continue;
      const texFields = parseObject(loaded, texMembers, [texRef.section, texRef.offset], { maxArrayRefs: 64 });
      const width = texFields.Width?.value ?? 0;
      const height = texFields.Height?.value ?? 0;
      const encoding = texFields.Encoding?.value ?? 0;
      const subFormat = texFields.SubFormat?.value ?? 0;
      const fromFileName = texFields.FromFileName?.value ?? "";
      const alpha = readAlphaFromLayout(loaded, texMembers, texFields, texRef);
      const imagesField = texFields.Images;
      const imageType = imagesField?.reference_type ?? null;
      const images = imageType ? readReferenceArrayObjects(
        loaded,
        imagesField.target ?? null,
        imagesField.count ?? 0,
        imageType,
        { maxCount: maxImages }
      ) : [];
      for (let ii = 0; ii < images.length; ii++) {
        const imgFields = images[ii].fields;
        const mipsField = imgFields.MIPLevels;
        const mipType = mipsField?.reference_type ?? null;
        const mips = mipType ? readReferenceArrayObjects(
          loaded,
          mipsField.target ?? null,
          mipsField.count ?? 0,
          mipType,
          { maxCount: maxMips }
        ) : [];
        for (let mi = 0; mi < mips.length; mi++) {
          const mipFields = mips[mi].fields;
          const pixelField = mipFields.Pixels ?? mipFields.PixelBytes;
          const pixelCount = pixelField?.count ?? 0;
          const pixelTarget = pixelField?.target ?? null;
          let pixelBytes = null;
          if (pixelTarget && pixelCount > 0) {
            const section = loaded.sectionsOriginal[pixelTarget.section];
            if (section && pixelTarget.offset >= 0 && pixelTarget.offset + pixelCount <= section.length) {
              pixelBytes = section.subarray(pixelTarget.offset, pixelTarget.offset + pixelCount);
            }
          }
          records.push(
            /** @type {TextureWalkRecord} */
            {
              texIdx: ti,
              imgIdx: ii,
              mipIdx: mi,
              width,
              height,
              encoding,
              subFormat,
              alpha,
              fromFileName,
              pixelBytes,
              pixelCount
            }
          );
        }
      }
    }
    return records;
  }
  function readAlphaFromLayout(loaded, texMembers, texFields, texRef) {
    try {
      const layoutField = texFields.Layout;
      if (!layoutField || layoutField.type !== "inline") return 1;
      let layoutMember = null;
      for (let i = 0; i < texMembers.length; i++) {
        if (texMembers[i].name === "Layout") {
          layoutMember = texMembers[i];
          break;
        }
      }
      if (!layoutMember || !layoutMember.referenceType) return 1;
      const refSection = layoutMember.referenceType.section;
      if (!loaded.sectionsOriginal[refSection]) return 1;
      const layoutMembers = parseTypeTree(loaded, [refSection, layoutMember.referenceType.offset]);
      const layoutOffset = layoutField.offset ?? 0;
      const layoutFields = parseObject(loaded, layoutMembers, [texRef.section, texRef.offset + layoutOffset]);
      const bpp = layoutFields.BytesPerPixel?.value;
      return bpp === 3 ? 0 : 1;
    } catch {
      return 1;
    }
  }

  // scripts/granny-preview/entry.js
  var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  function decode64(text) {
    const output = new Uint8Array(text.length / 4 * 3 - (text.endsWith("==") ? 2 : text.endsWith("=") ? 1 : 0));
    let n = 0;
    for (let i = 0; i < text.length; i += 4) {
      const bits = alphabet.indexOf(text[i]) << 18 | alphabet.indexOf(text[i + 1]) << 12 | Math.max(0, alphabet.indexOf(text[i + 2])) << 6 | Math.max(0, alphabet.indexOf(text[i + 3]));
      if (n < output.length) output[n++] = bits >>> 16;
      if (n < output.length) output[n++] = bits >>> 8;
      if (n < output.length) output[n++] = bits;
    }
    return output;
  }
  function encode64(bytes) {
    const chunks = [];
    let text = "";
    for (let i = 0; i < bytes.length; i += 3) {
      const bits = bytes[i] << 16 | (bytes[i + 1] ?? 0) << 8 | (bytes[i + 2] ?? 0);
      text += alphabet[bits >>> 18 & 63] + alphabet[bits >>> 12 & 63] + (i + 1 < bytes.length ? alphabet[bits >>> 6 & 63] : "=") + (i + 2 < bytes.length ? alphabet[bits & 63] : "=");
      if (text.length >= 16384) {
        chunks.push(text);
        text = "";
      }
    }
    chunks.push(text);
    return chunks.join("");
  }
  function load(input) {
    const file = parseGR2File(decode64(input.file));
    const sections = input.sections.map(decode64);
    file.sectionBytes = (section) => sections[section.index];
    for (const section of file.sections) section.compression = 0;
    const loaded = loadGR2(file);
    const root = parseObject(loaded, parseTypeTree(loaded, file.header.root_type), file.header.root_object);
    const art = root.ArtToolInfo;
    const artFields = art?.target && art?.reference_type ? parseObject(loaded, parseTypeTree(loaded, [art.reference_type.section, art.reference_type.offset]), [art.target.section, art.target.offset]) : {};
    return { loaded, root, artFields };
  }
  function point(matrix, position) {
    const [x, y, z] = position;
    return [matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12], matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13], matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14]];
  }
  function preview(input, companion) {
    const selected = load(input), source = companion ? load(companion) : selected;
    const { loaded, root, artFields } = source;
    if ((root.Meshes?.count ?? 0) > 128 || (root.Textures?.count ?? 0) > 128 || (root.Skeletons?.count ?? 0) > 16) throw Error("GR2 scene exceeds the model preview limits.");
    const meshes = extractMeshes(loaded, { maxMeshes: 128 }), skeletons = extractSkeletons(loaded, { maxSkeletons: 16, maxBones: 4096 });
    const models = extractModels(loaded, { maxModels: 128, maxBindings: 128 });
    const notes = [], missing = [], textures = [];
    let animation = null;
    try {
      animation = extractAnimations(selected.loaded, { maxAnimations: 1 })[0] ?? null;
    } catch (error) {
      notes.push("Animation could not be sampled; showing bind pose: " + error.message);
    }
    if (companion) notes.push("Matched model: " + companion.path);
    notes.push(animation ? "Static first animation frame; animation playback is not enabled." : "Static bind pose; animation playback is not enabled.");
    const poses = skeletons.map((s) => poseSkeletonAt(s, animation, 0));
    let pixelCount = 0;
    for (const record of walkTextureImages(loaded, { maxTextures: 128, maxImages: 1, maxMips: 1 })) {
      const key = "gr2-texture-" + record.texIdx;
      try {
        const w = record.width, h = record.height;
        if (!Number.isInteger(w) || !Number.isInteger(h) || w <= 0 || h <= 0 || w > 4096 || h > 4096 || pixelCount + w * h > 8 * 1024 * 1024) throw Error("texture exceeds preview limit");
        pixelCount += w * h;
        let pixels;
        if (record.encoding === 3) pixels = decodeIGCTexture({ Width: w, Height: h, Alpha: record.alpha, ImageData: record.pixelBytes });
        else if (record.encoding === 1 && record.pixelBytes?.length === w * h * 4) {
          pixels = new Uint8Array(w * h * 4);
          for (let p = 0; p < pixels.length; p += 4) {
            pixels[p] = record.pixelBytes[p + 2];
            pixels[p + 1] = record.pixelBytes[p + 1];
            pixels[p + 2] = record.pixelBytes[p];
            pixels[p + 3] = record.pixelBytes[p + 3];
          }
        } else throw Error("unsupported texture encoding " + record.encoding);
        textures.push({ key, width: w, height: h, rgba: encode64(pixels), name: record.fromFileName });
      } catch (error) {
        missing.push(key + ": " + error.message);
      }
    }
    const result = [];
    let vertices = 0, triangles = 0;
    const transformMesh = (mesh, model) => {
      vertices += mesh.positions.length;
      triangles += mesh.indices.length / 3;
      if (vertices > 5e5 || triangles > 1e6) throw Error("GR2 geometry exceeds preview limits.");
      const skeletonIndex = model?.skeletonIdx ?? 0, skeleton = skeletons[skeletonIndex], pose = poses[skeletonIndex];
      const boneIndices = skeleton ? new Map(skeleton.bones.map((b, i) => [b.name, i])) : /* @__PURE__ */ new Map();
      const placement = composeLocalMatrix(model?.initialPlacement);
      const positions = mesh.positions.map((position, i) => {
        const weights = mesh.vertexWeights[i] ?? [];
        let sum = 0;
        const skinned = [0, 0, 0];
        for (const binding of weights) {
          const boneIndex = boneIndices.get(mesh.boneBindings[binding.boneIndex]?.name), matrix = pose?.skinningMatrices[boneIndex];
          if (!matrix) continue;
          const p = point(matrix, position);
          sum += binding.weight;
          for (let axis = 0; axis < 3; axis++) skinned[axis] += p[axis] * binding.weight;
        }
        return point(placement, sum > 0 ? skinned.map((v) => v / sum) : position);
      });
      const materials = mesh.materials.map(() => "");
      for (let i = 0; i < materials.length; i++) {
        const texture = textures.find((t) => t.name === mesh.materials[i].textureFile);
        materials[i] = texture?.key ?? "";
        if (!texture && mesh.materials[i].textureFile) missing.push(mesh.materials[i].textureFile + " (texture unavailable)");
      }
      result.push({ name: mesh.name, positions, indices: mesh.indices, uvs: mesh.uvs, materials, groups: mesh.triangleGroups });
    };
    const included = /* @__PURE__ */ new Set();
    for (const model of models) for (const binding of model.meshBindings) {
      const mesh = meshes[binding.meshIdx];
      if (!mesh) continue;
      transformMesh(mesh, model);
      included.add(binding.meshIdx);
    }
    for (let i = 0; i < meshes.length; i++) if (!included.has(i)) transformMesh(meshes[i], null);
    let upAxis = [0, 0, 1];
    if (root.ArtToolInfo?.target && artFields.UpVector) {
      const data = loaded.sectionsOriginal[root.ArtToolInfo.target.section];
      const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
      upAxis = [0, 1, 2].map((i) => view.getFloat32(artFields.UpVector.offset + i * 4, true));
    }
    return JSON.stringify({ meshes: result, textures, missing: [...new Set(missing)], notes, upAxis, skeletonCount: skeletons.length, boneCount: skeletons.reduce((n, s) => n + s.bones.length, 0), animationName: animation?.name ?? "" });
  }
  return __toCommonJS(entry_exports);
})();
