/* Credential-free integration test of the bundled WASM and native bridge. */
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const assert = require("node:assert/strict");
const directory = path.resolve(__dirname, "../../Packages/ApplePackage/Sources/AppleSAPRuntime/Runtime");
globalThis.MUnicorn = require(path.join(directory, "unicorn_x86.js"));
require(path.join(directory, "wasm_exec.js"));
const payload = Buffer.from("Asspp credential-free SAP integration test");
const deadline = setTimeout(() => { console.error("SAP integration timed out"); process.exit(1); }, 180000);
globalThis.XMLHttpRequest = class {
    open(method, name) { assert.equal(method, "GET"); assert.equal(name, "sap.wasm"); }
    send() {
        const bytes = fs.readFileSync(path.join(directory, "sap.wasm"));
        this.response = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
        this.status = 200;
        this.onload();
    }
};
globalThis.window = {
    webkit: { messageHandlers: { sap: { postMessage: async message => {
        try {
            if (message.event === "ready") {
                console.log("SAP runtime ready");
                window.sapSignRequest("AABBCCDDEEFF", payload.toString("base64"));
            } else if (message.event === "request") {
                const url = message.kind === "certificate"
                    ? "https://s.mzstatic.com/sap/setupCert.plist"
                    : "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy";
                assert.ok(["certificate", "setup"].includes(message.kind));
                const options = message.kind === "setup" ? {
                    method: "POST", headers: { "Content-Type": "application/x-plist" },
                    body: Buffer.from(message.body, "base64")
                } : {};
                const response = await fetch(url, options);
                assert.equal(response.status, 200);
                const data = Buffer.from(await response.arrayBuffer());
                console.log(`SAP ${message.kind} accepted (${data.length} bytes)`);
                window.sapReply(message.id, data.toString("base64"), "");
            } else if (message.event === "signed") {
                const signature = Buffer.from(message.signature, "base64");
                assert.ok(signature.length > 0 && signature.length <= 65536);
                console.log(`SAP signature produced (${signature.length} bytes); no login credentials sent`);
                clearTimeout(deadline);
                process.exit(0);
            } else if (message.event === "failed") {
                throw new Error(message.message);
            }
        } catch (error) {
            console.error(error.message);
            clearTimeout(deadline);
            process.exit(1);
        }
    } } } }
};
vm.runInThisContext(fs.readFileSync(path.join(directory, "bridge.js"), "utf8"));
