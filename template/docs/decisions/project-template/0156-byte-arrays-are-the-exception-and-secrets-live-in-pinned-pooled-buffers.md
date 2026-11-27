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

## Decision

**Bytes travel as spans and memory, and `byte[]` appears only where an API or a framework demands one; a buffer that
may hold a secret is pinned, pooled, owned by one disposable, and zeroed with `CryptographicOperations.ZeroMemory` when
it is disposed.**

1. `byte[]` is the exception: only at the call to an API that takes or returns nothing else (wrap it at once as
   `ReadOnlyMemory<byte>`), in a type a framework binds that needs one (an EF Core column, a serialized DTO), and in
   tests. Inputs are `ReadOnlySpan<byte>`, or `ReadOnlyMemory<byte>` across `await` or in a field; outputs follow
   [ADR-0112](0112-binary-data-uses-spans-pooled-buffers-and-cleared-secrets.md) rule 1; a byte constant is a
   `static ReadOnlySpan<byte> Name => "…"u8;` or `=> [0x01, 0x02];` property. Call span overloads:
   `Encoding.GetBytes(ReadOnlySpan<char>, Span<byte>)`, `Convert.TryFromBase64Chars`, `RandomNumberGenerator.Fill`,
   `SHA256.HashData(ReadOnlySpan<byte>, Span<byte>)`, `HMACSHA256.HashData` with a destination span,
   `Rfc2898DeriveBytes.Pbkdf2` and `HKDF.DeriveKey` with an output span.
2. Sensitivity is stated where the buffer is made: every rental names it (`isSensitive: true` or `false`).
3. A sensitive buffer never moves: it comes from a pool of Pinned Object Heap arrays, from `GC.AllocateArray<T>` or
   `GC.AllocateUninitializedArray<T>` with `pinned: true` off hot paths, or from `stackalloc` for a small constant size
   (ADR-0112's gotchas). Never `new byte[]`, `ArrayPool<T>.Shared` or `MemoryPool<T>.Shared`, even with
   `clearArray: true`. This replaces ADR-0112 rules 2 and 3 for secrets, transient ones included.
4. One owner zeroes it: an `IMemoryOwner<T>` or a `ref struct` lifetime in a `using`, whose `Dispose` calls
   `CryptographicOperations.ZeroMemory`; no finalizer does it. A fill that throws disposes the owner first. Code reads
   only what it wrote. The element type is `unmanaged`: zeroing works on bytes, and zeroing a reference leaves the
   object it points to.
5. No secret goes in a type that copies it: the types and methods the Context lists. A growable sensitive writer copies
   into a larger pinned buffer and zeroes the old one; a `Stream` that holds a secret overrides the base members.
6. Secret text is encoded once, at the boundary, into a sensitive buffer, with a throwing encoding; it is not kept as a
   `string`, and `SecureString` is not used (Microsoft's DE0001).
7. A secret in a field is a sealed disposable type that owns one sensitive buffer, prints a fixed placeholder such as
   `[REDACTED]` from `ToString` and the debugger, and compares in fixed time
   ([ADR-0146](0146-secrets-are-never-logged-compared-in-constant-time-and-shown-once.md)).
8. A project that handles secrets takes these from NCode.Buffers, not a pool of its own, and may ban the shared pools in
   shipping code with a `BannedSymbols.<name>.txt`
   ([ADR-0102](0102-disallowed-apis-are-banned-at-build-time.md)), as
   [NCode.Buffers ADR-1003](https://github.com/NCodeGroup/Buffers/blob/main/docs/decisions/1003-shipping-code-takes-buffers-and-encodings-through-bufferfactory-and-secureencoding.md)
   does. It uses:
   - `BufferFactory.Rent(length, isSensitive: true, out Span<byte> buffer)`.
   - `SecureMemoryPool<T>.Shared` for an API that takes a `MemoryPool<T>`.
   - `BufferFactory.CreatePinnedArray(length)` for an API that needs a `T[]`.
   - `span.GetSecureLifetime()` over a `stackalloc`.
   - `BufferFactory.CreateContiguousBufferWriter(isSensitive: true)`,
     `BufferFactory.CreatePooledBufferWriter(isSensitive: true)` and
     `BufferFactory.CreatePooledStream(isSensitive: true)` for unknown lengths.
   - `new PooledTextBuilder(isSensitive: true)` and
     `SecureEncoding.UTF8.RentBytes(chars, isSensitive: true, out Span<byte> bytes)` for text.
   - `BinaryTextEncoding.RentDecoded(text, format, isSensitive: true, out Span<byte> bytes)` for Base64 and hex.
   - `BufferFactory.RentRandom(length, isSensitive: true, out Span<byte> key)`.
   - `Secret.Create<T>(value)` for a field.
9. Limits: pinning and zeroing neither lock pages nor hide them from a debugger, a dump, swap or hibernation
   ([NCode.Buffers ADR-1018](https://github.com/NCodeGroup/Buffers/blob/main/docs/decisions/1018-the-library-neither-locks-nor-encrypts-memory.md));
   a secret that must not be readable in the process stays in a key vault or HSM.

Existing `byte[]` surfaces convert as they are touched, not in one sweep.
