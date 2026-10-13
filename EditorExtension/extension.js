// NotchGate Bridge
//
// Each editor window listens on its own Unix socket:
//   ~/Library/Application Support/NotchGate/editors/<extension-host-pid>.sock
// NotchGate sends one JSON line per connection and gets one JSON line back:
//   {"type":"send","pids":[...],"text":"...","submit":true,"submitDelayMs":150}
//                                           (empty text + submit = press Return only)
//   {"type":"find","pids":[...]}            (is the session in this window?)
//   {"type":"ping"}
// `pids` is the Claude process and its ancestors; the matching terminal is
// the one whose shell is among them. The socket is user-only (0600).
'use strict';

const vscode = require('vscode');
const net = require('net');
const fs = require('fs');
const os = require('os');
const path = require('path');

const DIRECTORY = path.join(os.homedir(), 'Library', 'Application Support', 'NotchGate', 'editors');
const MAX_REQUEST_BYTES = 1024 * 1024;

let server;
let socketPath;

function activate(context) {
  if (process.platform !== 'darwin') return;
  try {
    fs.mkdirSync(DIRECTORY, { recursive: true, mode: 0o700 });
    socketPath = path.join(DIRECTORY, `${process.pid}.sock`);
    removeQuietly(socketPath);

    server = net.createServer(onConnection);
    server.on('error', (error) => console.error('[NotchGate] bridge error:', error.message));
    server.listen(socketPath, () => {
      try { fs.chmodSync(socketPath, 0o600); } catch (_) { /* best effort */ }
    });
    context.subscriptions.push({ dispose: shutdown });
  } catch (error) {
    console.error('[NotchGate] bridge failed to start:', error.message);
  }
}

function onConnection(connection) {
  let buffer = '';
  let handled = false;
  connection.setEncoding('utf8');
  connection.setTimeout(10000, () => connection.destroy());
  connection.on('error', () => {});
  connection.on('data', (chunk) => {
    if (handled) return;
    buffer += chunk;
    if (buffer.length > MAX_REQUEST_BYTES) return connection.destroy();
    const newline = buffer.indexOf('\n');
    if (newline < 0) return;
    handled = true;
    handle(buffer.slice(0, newline))
      .catch((error) => ({ ok: false, error: 'internal', message: String((error && error.message) || error) }))
      .then((response) => connection.end(JSON.stringify(response) + '\n'));
  });
}

async function handle(line) {
  let request;
  try { request = JSON.parse(line); } catch (_) { return { ok: false, error: 'bad-request' }; }

  if (request.type === 'ping') {
    return { ok: true, app: vscode.env.appName, terminals: vscode.window.terminals.length };
  }
  if (!Array.isArray(request.pids)) return { ok: false, error: 'bad-request' };

  const terminal = await findTerminal(request.pids);
  if (!terminal) return { ok: false, error: 'no-terminal' };
  if (request.type === 'find') return { ok: true, app: vscode.env.appName, terminal: terminal.name };
  if (request.type !== 'send' || typeof request.text !== 'string') return { ok: false, error: 'bad-request' };
  // Empty text with `submit` just presses Return (retrying a prompt that never went in).
  if (request.text.length === 0 && !request.submit) return { ok: false, error: 'bad-request' };

  if (request.text.length > 0) {
    terminal.sendText(request.text, false);
    // Return goes separately so Claude Code sees a key press, not pasted text.
    if (request.submit) await delay(clamp(Number(request.submitDelayMs) || 150, 50, 1000));
  }
  if (request.submit) terminal.sendText('\r', false);
  return { ok: true, app: vscode.env.appName };
}

async function findTerminal(pids) {
  const wanted = new Set(pids.map(Number));
  for (const terminal of vscode.window.terminals) {
    let pid;
    try { pid = await terminal.processId; } catch (_) { continue; }
    if (pid && wanted.has(pid)) return terminal;
  }
  return undefined;
}

function shutdown() {
  if (server) {
    server.close();
    server = undefined;
  }
  if (socketPath) removeQuietly(socketPath);
}

function removeQuietly(file) {
  try { fs.unlinkSync(file); } catch (_) { /* already gone */ }
}

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

module.exports = { activate, deactivate: shutdown };
