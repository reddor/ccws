
var proc;
var log = [];
var currentLine = "";

var clients = new BulkSender();

function processInput(input) {
    clients.send(input);
    let inp = input.split("\n");
    if (inp.length == 0) return;
    currentLine += inp[0];
    if (inp.length > 1) {
        for (let i = 1; i < inp.length; i++) {
            log.push(currentLine);
            currentLine = inp[i];
        }
    }
}

function initProc() {
    proc = new Process(system.getEnvVar("target"), system.getEnvVar("params"));
    proc.addEventListener("data", e => processInput(e.data));
    proc.start();
    clients.send("----------------------------- new build -----------------------------\n");
}

handler.addEventListener("connect", e => {
    if (!proc || ((e.client.parameter == "build") && proc.isTerminated())) {
        log = [];
        currentLine = "";
        initProc();
    }

    e.client.send(log.join("\n"));
    e.client.send(((log.length>0) ? "\n" : "") + currentLine);
    clients.add(e.client);
});

handler.addEventListener("disconnect", e=> clients.remove(e.client));
handler.addEventListener("data", e => {
    if((e.data == "rebuild") && (proc.isTerminated())) {
        log = [];
        currentLine = "";
        initProc();
    }
});
handler.addEventListener("request", e => {
    e.client.mimeType = "text/json; charset=utf-8";

    if (!proc || ((e.client.parameter == "build") && proc.isTerminated())) {
        log = [];
        currentLine = "";
        initProc();
    }
    e.client.send(JSON.stringify({ "status": proc.isTerminated() ? "stopped" : "running", currentLine, "exitCode": proc.exitCode, log }));
    e.client.disconnect();
});