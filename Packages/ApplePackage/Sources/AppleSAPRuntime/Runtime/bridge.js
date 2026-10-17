/* Native-only SAP transport. Login bytes stay inside this WebView. */
"use strict";
(() => {
    const pending = new Map();
    let sequence = 0;
    let initialized = false;
    let sessionGuid = null;
    const notify = (event, fields = {}) =>
        window.webkit.messageHandlers.sap.postMessage({ event, ...fields });
    window.sapReply = (id, body, error) => {
        const operation = pending.get(id);
        if (!operation) return;
        pending.delete(id);
        if (error) operation.reject(new Error(error));
        else operation.resolve(body);
    };
    const request = (kind, body = "") => new Promise((resolve, reject) => {
        const id = String(++sequence);
        pending.set(id, { resolve, reject });
        notify("request", { id, kind, body });
    });
    const memoryShims = new Set([
        "_malloc", "_malloc_good_size", "_calloc", "_free", "_memcpy",
        "_memmove", "_memset", "___bzero", "___memcpy_chk", "___memset_chk",
        "_strlen", "_pthread_once", "_pthread_mutex_lock", "_pthread_mutex_unlock",
        "_pthread_rwlock_init", "_pthread_rwlock_init$UNIX2003",
        "_pthread_rwlock_unlock", "_pthread_rwlock_unlock$UNIX2003",
        "_pthread_rwlock_wrlock", "_pthread_rwlock_wrlock$UNIX2003"
    ]);
    function installShims() {
        const shims = new Map();
        const native = [];
        globalThis.sapWasmShimHandled = false;
        globalThis.sapWasmRegisterShim = (address, name) => {
            const value = BigInt(address);
            shims.set(value, name);
            if (memoryShims.has(name)) native.push(value);
        };
        globalThis.sapWasmTrapHook = (engine, address) => {
            globalThis.sapWasmShimHandled = false;
            const value = BigInt.asUintN(64, BigInt(address));
            const name = shims.get(value);
            if (memoryShims.has(name)) return;
            if (!name && native.some(start => value > start && value < start + 64n)) return;
            engine.emu_stop();
        };
    }
    function readWasm() {
        return new Promise((resolve, reject) => {
            const xhr = new XMLHttpRequest();
            xhr.open("GET", "sap.wasm");
            xhr.responseType = "arraybuffer";
            xhr.onload = () => xhr.response && (xhr.status === 0 || xhr.status === 200)
                ? resolve(xhr.response) : reject(new Error("SAP runtime could not be read"));
            xhr.onerror = () => reject(new Error("SAP runtime could not be read"));
            xhr.send();
        });
    }
    function result(value) {
        const parsed = JSON.parse(value);
        if (parsed.error) throw new Error(parsed.error);
        return parsed;
    }
    let initializationStage = "Unicorn";
    const ready = (async () => {
        globalThis.unicornModule = await MUnicorn();
        installShims();
        initializationStage = "Go runtime";
        const go = new Go();
        initializationStage = "local WASM read";
        const bytes = await readWasm();
        initializationStage = "WASM instantiate";
        const wasm = await WebAssembly.instantiate(bytes, go.importObject);
        initializationStage = "Go startup";
        go.run(wasm.instance).catch(() => notify("failed", { message: "SAP runtime stopped" }));
        while (!globalThis.sapWasmSignerReady) await new Promise(resolve => setTimeout(resolve, 10));
        for (const name of ["sapWasmPrepareSetup", "sapWasmFinishSetup", "sapWasmSign", "sapWasmClose"]) {
            if (typeof globalThis[name] !== "function") throw new Error("Unsupported SAP runtime");
        }
        notify("ready");
    })();
    ready.catch(error => notify("failed", {
        message: `SAP initialization failed (${initializationStage}): ${String(error.message || error).slice(0, 250)}`
    }));
    window.sapSignRequest = async (guid, body) => {
        try {
            await ready;
            if (!initialized || guid !== sessionGuid) {
                if (initialized) result(sapWasmClose());
                initialized = false;
                const certificate = await request("certificate");
                const setup = result(sapWasmPrepareSetup(guid, certificate));
                const reply = await request("setup", setup.requestBase64);
                if (result(sapWasmFinishSetup(reply)).ready !== true) throw new Error("SAP setup failed");
                initialized = true;
                sessionGuid = guid;
            }
            const signature = result(sapWasmSign(body)).signatureBase64;
            if (typeof signature !== "string" || !signature.length) throw new Error("Empty SAP signature");
            notify("signed", { signature });
        } catch (_) {
            initialized = false;
            notify("failed", { message: "Apple SAP handshake or signing failed" });
        }
    };
})();
