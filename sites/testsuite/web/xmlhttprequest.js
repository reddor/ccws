
function testXmlHttpRequest(success, failure) {
	var r = new XMLHttpRequest();
	r.open("GET", "/test/xmlhttprequest");
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
