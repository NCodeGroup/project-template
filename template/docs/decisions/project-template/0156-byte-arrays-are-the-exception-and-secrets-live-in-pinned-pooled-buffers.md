# 0156. Byte arrays are the exception, and secrets live in pinned, pooled buffers zeroed on dispose

- **Status:** Accepted
- **Date:** 2026-11-27
- **Amends:** 0112

## Context

This decision applies to .NET code that handles bytes. Its rules on secrets bind code that handles secrets, as
[ADR-0146](0146-secrets-are-never-logged-compared-in-constant-time-and-shown-once.md) item 1 defines them, plus
decrypted plaintext, derived key material, and the bytes of decoded secret text.

[ADR-0112](0112-binary-data-uses-spans-pooled-buffers-and-cleared-secrets.md) makes spans and caller-owned writers the
default and clears secrets, but it leaves three gaps:

- It names no place where `byte[]` still belongs.
- It lets a transient secret live in an `ArrayPool<byte>.Shared` array returned with `clearArray: true`, and pins only
  long-lived secrets.
- It says nothing of the types that copy data.

An array from `new byte[]` or `ArrayPool<byte>.Shared` is an ordinary heap object. A compacting collection can move it,
and zeroing clears only its last location, not the copy the move left. The shared pool hands the same arrays to every
component in the process, and `clearArray` is a per-call flag a caller can forget.

Some types and methods leave copies that nothing zeroes:

- `MemoryStream`, `ArrayBufferWriter<T>`, `StringBuilder` and `List<byte>` drop each array they outgrow.
- `Encoding.GetBytes(string)`, `Convert.FromBase64String`, `Convert.FromHexString(string)`,
  `RandomNumberGenerator.GetBytes(int)` and `.ToArray()` return new arrays.
- `Stream`'s base `Read(Span<byte>)`, `Write(ReadOnlySpan<byte>)`, `ReadByte`, `WriteByte` and `CopyTo` copy through
  arrays nothing zeroes, as
  [NCode.Buffers ADR-1027](https://github.com/NCodeGroup/Buffers/blob/main/docs/decisions/1027-text-base64-hex-and-random-helpers-rent-their-output-and-return-its-owner.md)
  and
  [NCode.Buffers ADR-1028](https://github.com/NCodeGroup/Buffers/blob/main/docs/decisions/1028-growable-writers-streams-and-text-builders-zero-each-buffer-they-outgrow.md)
  record.
- A `string` cannot be zeroed.

`GC.AllocateArray<T>(length, pinned: true)` and `GC.AllocateUninitializedArray<T>(length, pinned: true)` allocate on the
Pinned Object Heap, whose objects the collector never moves and frees only in a generation 2 collection. Allocating
there costs more than an ordinary allocation, so a hot path pools such arrays. An uninitialized array can hold memory
other code used, as Microsoft's documentation of `GC.AllocateUninitializedArray` warns.

NCode.Buffers (package `NCode.Buffers`, https://github.com/NCodeGroup/Buffers, site https://buffers.ncode.io/)
implements these rules. It keeps a pool of pinned 4096-byte buffers, zeroed with `CryptographicOperations.ZeroMemory`
when returned and dropped under memory pressure
([NCode.Buffers ADR-1012](https://github.com/NCodeGroup/Buffers/blob/main/docs/decisions/1012-the-secure-pool-caches-buffers-of-one-4096-byte-page.md),
[NCode.Buffers ADR-1015](https://github.com/NCodeGroup/Buffers/blob/main/docs/decisions/1015-the-secure-pools-cache-has-no-size-limit-and-is-dropped-under-memory-pressure.md)),
and a factory that takes `isSensitive` at every rental.
