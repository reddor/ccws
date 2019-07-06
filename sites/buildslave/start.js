(function(site) {
    
function addBuildTarget(name, target, params) {
    site.addWhitelistExecutable(target);
    ws = site.addWebsocket("/api/build/"+name, "buildslave.js");
    ws.setEnvVar("target", target);
    ws.setEnvVar("params", params);
}

addBuildTarget("ccws", "build-ccws.sh", "build");
})
  
