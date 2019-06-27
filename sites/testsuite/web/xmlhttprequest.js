
function testXmlHttpRequest(success, failure) {
	var r = new XMLHttpRequest();
	var url = location.protocol+'//'+location.hostname+(location.port ? ':'+location.port: '') + "/dummy.txt";
	console.log("Fetching ", url);
	r.open("GET", "/test/xmlhttprequest?" + encodeURI(url));
	// seems this is illegal after all
	//r.setRequestHeader("X-Unicode", "🍕");
	r.addEventListener("load", function(e) {
		r.responseText.indexOf("FAIL:") != 0 ? success() : failure("got "+r.responseText);
	});
	r.addEventListener("error", function(e) {
		failure("XMLHttpRequest error");
	});
	r.send();
}
