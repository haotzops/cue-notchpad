#!/usr/bin/env python3
"""Build Cue's compact, read-only cl100k token rank index.

The source .tiktoken file is kept for provenance. The app ships only this
binary index so runtime lookup does not construct 100,256 Swift Array keys.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import pathlib
import struct
import sys

MAGIC = b"CUEBPE01"
VERSION = 1
BUCKET_COUNT = 1 << 17
EXPECTED_TOKEN_COUNT = 100_256
EXPECTED_SOURCE_SHA256 = "223921b76ee99bde995b7ff738513eef100fb51d18c93597a113bcffe865b2a7"
HEADER = struct.Struct("<8sIIIIII")
ENTRY = struct.Struct("<IIII")
UINT32 = struct.Struct("<I")
EMPTY = 0


def fnv1a32(value: bytes) -> int:
    result = 0x811C9DC5
    for byte in value:
        result = ((result ^ byte) * 0x01000193) & 0xFFFFFFFF
    return result


def load_tokens(path: pathlib.Path) -> list[tuple[bytes, int]]:
    source = path.read_bytes()
    digest = hashlib.sha256(source).hexdigest()
    if digest != EXPECTED_SOURCE_SHA256:
        raise ValueError(f"unexpected cl100k source SHA-256: {digest}")

    tokens: list[tuple[bytes, int]] = []
    token_values: set[bytes] = set()
    ranks: set[int] = set()
    for line_number, line in enumerate(source.splitlines(), 1):
        try:
            encoded, rank_text = line.split(b" ", 1)
            token = base64.b64decode(encoded, validate=True)
            rank = int(rank_text)
        except (ValueError, TypeError) as error:
            raise ValueError(f"invalid vocabulary line {line_number}") from error
        if not token or len(token) > 255:
            raise ValueError(f"unsupported token length on line {line_number}")
        if token in token_values:
            raise ValueError(f"duplicate token on line {line_number}")
        if rank in ranks:
            raise ValueError(f"duplicate rank {rank}")
        token_values.add(token)
        ranks.add(rank)
        tokens.append((token, rank))

    if len(tokens) != EXPECTED_TOKEN_COUNT:
        raise ValueError(f"expected {EXPECTED_TOKEN_COUNT} tokens, found {len(tokens)}")
    if ranks != set(range(EXPECTED_TOKEN_COUNT)):
        raise ValueError("cl100k ranks are not contiguous")
    return tokens


def build_index(tokens: list[tuple[bytes, int]]) -> bytes:
    buckets = [EMPTY] * BUCKET_COUNT
    entries: list[bytes] = []
    blob = bytearray()
    maximum_chain = 0

    for entry_index, (token, rank) in enumerate(tokens):
        token_offset = len(blob)
        if token_offset >= 1 << 24:
            raise ValueError("token byte blob exceeds 24-bit offset")
        blob.extend(token)

        hash_value = fnv1a32(token)
        bucket = hash_value & (BUCKET_COUNT - 1)
        next_entry = buckets[bucket]
        offset_and_length = token_offset | (len(token) << 24)
        entries.append(ENTRY.pack(hash_value, offset_and_length, rank, next_entry))
        buckets[bucket] = entry_index + 1

    # Check chain shape as a deterministic guard against hash/index mistakes.
    for head in buckets:
        length = 0
        while head:
            length += 1
            head = ENTRY.unpack(entries[head - 1])[3]
        maximum_chain = max(maximum_chain, length)
    if maximum_chain > 16:
        raise ValueError(f"unexpectedly long hash chain: {maximum_chain}")

    entry_offset = HEADER.size + BUCKET_COUNT * UINT32.size
    blob_offset = entry_offset + len(entries) * ENTRY.size
    result = bytearray(HEADER.pack(
        MAGIC,
        VERSION,
        BUCKET_COUNT,
        len(tokens),
        entry_offset,
        blob_offset,
        len(blob),
    ))
    result.extend(struct.pack(f"<{BUCKET_COUNT}I", *buckets))
    result.extend(b"".join(entries))
    result.extend(blob)
    output = bytes(result)
    verify_index(output, tokens)
    return output


def verify_index(index: bytes, tokens: list[tuple[bytes, int]]) -> None:
    magic, version, bucket_count, token_count, entry_offset, blob_offset, blob_size = HEADER.unpack_from(index)
    if magic != MAGIC or version != VERSION or token_count != len(tokens):
        raise ValueError("generated index header failed verification")
    if blob_offset + blob_size != len(index):
        raise ValueError("generated index bounds failed verification")

    for token, expected_rank in tokens:
        hash_value = fnv1a32(token)
        head = UINT32.unpack_from(index, HEADER.size + (hash_value & (bucket_count - 1)) * 4)[0]
        while head:
            entry_hash, offset_and_length, rank, head = ENTRY.unpack_from(
                index, entry_offset + (head - 1) * ENTRY.size
            )
            offset = offset_and_length & 0x00FFFFFF
            length = offset_and_length >> 24
            if entry_hash == hash_value and index[blob_offset + offset:blob_offset + offset + length] == token:
                if rank != expected_rank:
                    raise ValueError(f"rank mismatch for token {token!r}")
                break
        else:
            raise ValueError(f"token missing from generated index: {token!r}")


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=pathlib.Path,
        default=root / "Supporting/Tokenizer/cl100k_base.tiktoken",
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=root / "Sources/CueCore/Resources/Tokenizer/cl100k_base.cuebpe",
    )
    args = parser.parse_args()

    try:
        output = build_index(load_tokens(args.source))
    except (OSError, ValueError) as error:
        print(f"generate-tokenizer-index: {error}", file=sys.stderr)
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if not args.output.exists() or args.output.read_bytes() != output:
        args.output.write_bytes(output)
    print(f"Generated {args.output} ({len(output):,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
