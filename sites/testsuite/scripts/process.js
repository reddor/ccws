
handler.addEventListener("request", e => {
    let client = e.client;
    client.mimeType = "text/plain; charset=utf-8";
    try {
      let process = new Process('../../../ccws', '-debug', '-test');
      let data = "";
      process.addEventListener('data', e => data += e.data);
      process.addEventListener('terminate', e => {
        let msg = e.exitCode == 0 ? "ccws -debug -test output:\n" : 
        "FAIL: ccws -debug -test terminated with exitcode " + e.exitCode + ":\n";
        client.send(msg);
        client.send(data);
        client.disconnect();
      });
      process.start();
    } catch(e) {
        client.send("FAIL: "+e.message);
        client.disconnect();
    }
});

let g = new GlobalEventListener('Test'); g.addEventListener("ping", e => { g.globalDispatch("pong", "Process Test")});
