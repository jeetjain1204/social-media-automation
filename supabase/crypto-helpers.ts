/**
 * Ensure we always pass exactly 32 bytes (256-bit) to AES-GCM.
 * – If the supplied env key is shorter, we zero-pad
 * – If longer, we truncate
 * NOTE: For real production, prefer a random 32-byte key stored in Vault.
 */

function toKeyBytes(key: string): Uint8Array {
  const raw = new TextEncoder().encode(key);
  if (raw.length === 32) return raw;
  if (raw.length > 32) return raw.slice(0, 32);

  const padded = new Uint8Array(32);
  padded.set(raw);
  return padded;
}

export async function encryptToken(
  data: string,
  key: string,
): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    toKeyBytes(key),
    { name: "AES-GCM" },
    false,
    ["encrypt"],
  );

  const cipher = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    cryptoKey,
    new TextEncoder().encode(data),
  );

  const combined = new Uint8Array(iv.length + cipher.byteLength);
  combined.set(iv);
  combined.set(new Uint8Array(cipher), iv.length);

  return btoa(String.fromCharCode(...combined));
}

export async function decryptToken(
  encryptedB64: string,
  key: string,
): Promise<string> {
  const bytes = Uint8Array.from(atob(encryptedB64), (c) => c.charCodeAt(0));
  const iv = bytes.slice(0, 12);
  const data = bytes.slice(12);

  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    toKeyBytes(key),
    { name: "AES-GCM" },
    false,
    ["decrypt"],
  );

  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    cryptoKey,
    data,
  );

  return new TextDecoder().decode(plain);
}
