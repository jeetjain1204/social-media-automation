// kv_redis.ts — FIXED: send raw JSON array to Upstash
// Env: UPSTASH_REDIS_REST_URL, UPSTASH_REDIS_REST_TOKEN

export type RedisKVOptions = {
  url?: string;
  token?: string;
  namespace?: string; // optional key prefix
};

export interface KVStore {
  get<T = unknown>(key: string): Promise<{ value: T; exp: number } | null>;
  set<T = unknown>(key: string, value: T, ttlSec: number): Promise<void>;
  del?(key: string): Promise<void>;
  acquireLock?(key: string, ttlSec: number): Promise<boolean>;
  releaseLock?(key: string): Promise<void>;
}

export function createRedisKV(opts: RedisKVOptions = {}): KVStore {
  const url = opts.url ?? Deno.env.get("UPSTASH_REDIS_REST_URL")!;
  const token = opts.token ?? Deno.env.get("UPSTASH_REDIS_REST_TOKEN")!;
  if (!url || !token) {
    throw new Error("Upstash Redis env missing: UPSTASH_REDIS_REST_URL/UPSTASH_REDIS_REST_TOKEN");
  }
  const ns = (opts.namespace ?? "edge") + ":";

  // ✅ Upstash expects the body to be a JSON array like ["GET","key"]
  async function upstash(cmd: string[]) {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(cmd),
    });
    const json = await res.json();
    if (!res.ok) {
      throw new Error(`Upstash error ${res.status}: ${JSON.stringify(json)}`);
    }
    return json.result;
  }

  return {
    async get<T>(key: string) {
      const v = await upstash(["GET", ns + key]);
      if (v == null) return null;
      try {
        const obj = JSON.parse(v);
        if (typeof obj?.exp === "number" && obj.exp < Date.now()) return null;
        return obj as { value: T; exp: number };
      } catch {
        return null;
      }
    },
    async set<T>(key: string, value: T, ttlSec: number) {
      const payload = JSON.stringify({ value, exp: Date.now() + ttlSec * 1000 });
      // SET key value EX ttl
      await upstash(["SET", ns + key, payload, "EX", String(ttlSec)]);
    },
    async del(key: string) {
      await upstash(["DEL", ns + key]);
    },
    async acquireLock(key: string, ttlSec: number) {
      // SET lock:<key> 1 NX EX ttl
      const ok = await upstash(["SET", ns + "lock:" + key, "1", "NX", "EX", String(ttlSec)]);
      return ok === "OK";
    },
    async releaseLock(key: string) {
      await upstash(["DEL", ns + "lock:" + key]);
    },
  };
}
