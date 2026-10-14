// Cloudflare Worker entry. One Durable Object holds the whole list, so every
// request sees the same lobbies. Cloudflare unloads an idle object after a few
// seconds, so the list is also kept in the object's storage and reloaded.
import { Directory } from "./directory.js";

const reply = (status, body) => new Response(JSON.stringify(body), {
    status, headers: { "content-type": "application/json", "cache-control": "no-store" },
});

export class LobbyDirectory {
    constructor(state) {
        this.storage = state.storage;
        this.directory = new Directory();
        state.blockConcurrencyWhile(async () => {
            for (const [id, lobby] of await this.storage.list()) this.directory.lobbies.set(id, lobby);
        });
    }
    async fetch(request) {
        const url = new URL(request.url);
        const body = request.method === "GET" ? "" : await request.text();
        const result = await this.directory.handle(request.method, url.pathname, body,
            request.headers.get("x-client") ?? "");
        if (result.saved) await this.storage.put(result.saved.id, result.saved);
        if (result.removed.length) await this.storage.delete(result.removed);
        return reply(result.status, result.body);
    }
}

// Compares every character whatever the result, so the time taken says
// nothing about how much of a guess was right.
const sameText = (a, b) => {
    let different = a.length ^ b.length;
    for (let i = 0; i < b.length; i++) different |= (a.charCodeAt(i % Math.max(1, a.length)) || 0) ^ b.charCodeAt(i);
    return different === 0;
};

export default {
    async fetch(request, env) {
        // Official builds of the game send the password in X-Lobby-Key. It is
        // set as the secret LOBBY_KEY on this worker and is not in the public
        // source. Until that secret is set, the list is open to everyone.
        const wanted = String(env.LOBBY_KEY ?? "");
        if (wanted && !sameText(request.headers.get("x-lobby-key") ?? "", wanted)) {
            return reply(401, { error: "key" });
        }
        const forwarded = new Request(request);
        forwarded.headers.set("x-client", request.headers.get("cf-connecting-ip") ?? "");
        return env.DIRECTORY.get(env.DIRECTORY.idFromName("global")).fetch(forwarded);
    },
};
