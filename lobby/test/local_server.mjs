// Runs the same lobby list logic on this machine for testing: node test/local_server.mjs [port]
import http from "node:http";
import { Directory } from "../src/directory.js";
const directory = new Directory();
const port = Number(process.argv[2] ?? 8787);
http.createServer(async (request, response) => {
    let body = "";
    for await (const chunk of request) body += chunk;
    const result = await directory.handle(request.method, new URL(request.url, "http://x").pathname, body,
        request.socket.remoteAddress ?? "");
    response.writeHead(result.status, { "content-type": "application/json" });
    response.end(JSON.stringify(result.body));
}).listen(port, "127.0.0.1", () => console.log("lobby list on http://127.0.0.1:" + port));
