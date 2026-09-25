// Minimal static file server for the release web build.
//
// `flutter build web` output is ES-module based and needs correct MIME types and
// a real HTTP origin — opening `build/web/index.html` over file:// fails. This
// exists because there is no Python on this machine and Flutter's own
// `run -d web-server` recompiles in debug.
//
// Usage: node tool/serve_web.js [port]

const http = require('http');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', 'build', 'web');
const port = Number(process.argv[2] ?? 8080);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.map': 'application/json; charset=utf-8',
};

if (!fs.existsSync(root)) {
  console.error(`No build found at ${root} — run "flutter build web" first.`);
  process.exit(1);
}

http
  .createServer((req, res) => {
    // Strip the query string; Flutter's bootstrap requests carry a version hash.
    let urlPath = decodeURIComponent(req.url.split('?')[0]);
    if (urlPath === '/' || urlPath === '') urlPath = '/index.html';

    const filePath = path.join(root, urlPath);

    // Refuse to escape the build directory.
    if (!filePath.startsWith(root)) {
      res.writeHead(403).end('Forbidden');
      return;
    }

    fs.readFile(filePath, (err, data) => {
      if (err) {
        // SPA fallback: unknown paths render the app shell.
        fs.readFile(path.join(root, 'index.html'), (e2, shell) => {
          if (e2) {
            res.writeHead(404).end('Not found');
            return;
          }
          res.writeHead(200, { 'Content-Type': MIME['.html'] }).end(shell);
        });
        return;
      }

      const type = MIME[path.extname(filePath).toLowerCase()] ?? 'application/octet-stream';
      res.writeHead(200, { 'Content-Type': type }).end(data);
    });
  })
  .listen(port, () => {
    console.log(`Closey web build served at http://localhost:${port}`);
  });
