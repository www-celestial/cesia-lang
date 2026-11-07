const product = { Id: 7, Name: "bread", Price: 1.25, Tags: ["fresh", "warm"] }
require("http").createServer((q, r) => {
  if (q.url === "/json") {
    const body = JSON.stringify(product)
    r.setHeader("Content-Type", "application/json")
    r.setHeader("Content-Length", Buffer.byteLength(body))
    r.end(body)
  } else {
    r.setHeader("Content-Length", 5)
    r.end("Cesia")
  }
}).listen(19101)
