// Gzowo Concierge - minimal RFC 6455 WebSocket server (no dependencies): text, binary, ping/pong, close.
import crypto from 'node:crypto';

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

function encode(opcode, payload) {
  const len = payload.length;
  const head = len < 126 ? Buffer.from([0x80 | opcode, len]) : len < 65536 ? Buffer.from([0x80 | opcode, 126, len >> 8, len & 255]) : (() => { const b = Buffer.alloc(10); b[0] = 0x80 | opcode; b[1] = 127; b.writeBigUInt64BE(BigInt(len), 2); return b; })();
  return Buffer.concat([head, payload]);
}

export function acceptUpgrade(req, socket, { onMessage, onClose, maxFrame = 1 << 20 }) {
  const key = req.headers['sec-websocket-key'];
  if (!key || req.headers.upgrade?.toLowerCase() !== 'websocket') { socket.destroy(); return null; }
  const accept = crypto.createHash('sha1').update(key + GUID).digest('base64');
  socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
  socket.setNoDelay(true);

  let buf = Buffer.alloc(0), frag = [], fragOp = 0, closed = false;
  const finish = () => { if (closed) return; closed = true; onClose?.(); };
  const write = b => { if (!closed && socket.writable) socket.write(b); };

  const conn = {
    sendText: s => write(encode(0x1, Buffer.from(s))),
    sendBinary: b => write(encode(0x2, Buffer.isBuffer(b) ? b : Buffer.from(b))),
    close: (code = 1000) => { if (closed) return; const p = Buffer.alloc(2); p.writeUInt16BE(code); write(encode(0x8, p)); socket.end(); finish(); },
    get open() { return !closed && socket.writable; },
  };

  function parse() {
    for (;;) {
      if (buf.length < 2) return;
      const fin = !!(buf[0] & 0x80), op = buf[0] & 0x0f, masked = !!(buf[1] & 0x80);
      let len = buf[1] & 0x7f, off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      if (len > maxFrame) { conn.close(1009); socket.destroy(); return; }
      if (!masked) { conn.close(1002); socket.destroy(); return; }
      if (buf.length < off + 4 + len) return;
      const mask = buf.subarray(off, off + 4);
      const data = Buffer.from(buf.subarray(off + 4, off + 4 + len));
      for (let i = 0; i < data.length; i++) data[i] ^= mask[i & 3];
      buf = buf.subarray(off + 4 + len);
      if (op === 0x8) { conn.close(1000); return; }
      if (op === 0x9) { write(encode(0xA, data)); continue; }
      if (op === 0xA) continue;
      if (op === 0x0 || op === 0x1 || op === 0x2) {
        if (op !== 0x0) { frag = []; fragOp = op; }
        frag.push(data);
        if (fin) { const full = Buffer.concat(frag); frag = []; onMessage?.(fragOp === 0x1 ? full.toString('utf8') : full, fragOp === 0x2); }
      }
    }
  }

  socket.on('data', d => { buf = Buffer.concat([buf, d]); try { parse(); } catch { socket.destroy(); } });
  socket.on('close', finish);
  socket.on('error', finish);
  return conn;
}
