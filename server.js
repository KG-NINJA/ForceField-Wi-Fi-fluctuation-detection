const fs = require("fs");
const http = require("http");
const path = require("path");
const { WebSocketServer, WebSocket } = require("ws");

const PORT = 8080;
const INDEX_PATH = path.join(__dirname, "index.html");

const server = http.createServer((req, res) => {
  const requestPath = req.url === "/" ? "/index.html" : req.url;

  if (requestPath !== "/index.html") {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Not found");
    return;
  }

  fs.readFile(INDEX_PATH, (err, data) => {
    if (err) {
      res.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("Failed to load index.html");
      return;
    }

    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(data);
  });
});

const wss = new WebSocketServer({ server });

wss.on("error", (error) => {
  if (error && error.code === "EADDRINUSE") {
    console.error("Port 8080 is already in use.");
    return;
  }
  console.error("WebSocket server error:", error);
});

wss.on("connection", (ws) => {
  console.log("Client connected");

  ws.on("message", (rawMessage) => {
    let payload;
    try {
      payload = JSON.parse(rawMessage.toString());
    } catch (error) {
      return;
    }

    if (
      typeof payload !== "object" ||
      payload === null ||
      !Number.isFinite(payload.score) ||
      !Number.isFinite(payload.latency)
    ) {
      return;
    }

    const normalized = {
      score: Number(payload.score),
      latency: Number(payload.latency),
      micro: Number.isFinite(payload.micro) ? Number(payload.micro) : 0,
    };

    console.log(
      `Score ${normalized.score} latency ${normalized.latency} micro ${normalized.micro}`
    );

    const outbound = JSON.stringify(normalized);
    for (const client of wss.clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(outbound);
      }
    }
  });
});

server.on("error", (error) => {
  if (error && error.code === "EADDRINUSE") {
    console.error("Port 8080 is already in use. Stop the existing process or use it.");
    return;
  }
  console.error("HTTP server error:", error);
});

server.listen(PORT, () => {
  console.log(`Server listening on http://localhost:${PORT}`);
});
