import client from "./client.wasm";

function readIOVec(
  view: DataView,
  iovs_ptr: number,
  iovs_len: number,
): Array<Uint8Array> {
  let result = Array<Uint8Array>(iovs_len);

  for (let i = 0; i < iovs_len; i++) {
    const bufferPtr = view.getUint32(iovs_ptr, true);
    iovs_ptr += 4;

    const bufferLen = view.getUint32(iovs_ptr, true);
    iovs_ptr += 4;

    result[i] = new Uint8Array(view.buffer, bufferPtr, bufferLen);
  }
  return result;
}

const inst = await WebAssembly.instantiateStreaming(fetch(client), {
  wasi_snapshot_preview1: {
    fd_write: (fd: number, ciovs_ptr: number, ciovs_len: number, retptr: number) => {
      const view = new DataView(inst.instance.exports.memory.buffer);
      const iovs = readIOVec(view, ciovs_ptr, ciovs_len);
      const decoder = new TextDecoder();

      let bytesWritten = 0;
      for (const iov of iovs) {
        if (iov.byteLength === 0) continue;

        if (fd === 1 || fd === 2) {
          const output = decoder.decode(iov);
          console.log(output);
        } else {
          return 44;
        }

        bytesWritten += iov.byteLength;
      }

      view.setUint32(retptr, bytesWritten, true);
      return 0;
    },
    proc_exit: () => {},
  },
});

console.log(inst);

inst.instance.exports._start();
