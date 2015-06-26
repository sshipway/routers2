var requiredMajorVersion = 9;
var requiredMinorVersion = 0;
var requiredRevision = 45;
if (AC_FL_RunContent == 0 || DetectFlashVer == 0) {
	alert("This page requires AC_RunActiveContent.js.");
} else {
	var hasRightVersion = DetectFlashVer(requiredMajorVersion, requiredMinorVersion, requiredRevision);
	if(!hasRightVersion) { 
		var alternateContent = 'This content requires the Adobe Flash Player. '
		+ '<u><a href=http://www.macromedia.com/go/getflash/>Get Flash</a></u>.';
		document.write(alternateContent); 
	}
}
function gauge(cfg,target) {
  AC_FL_RunContent(
      'codebase', 'https://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,45,0',
      'width', '200',
      'height', '300',
      'scale', 'noscale',
      'salign', 'TL',
      'bgcolor', '#cccccc',
      'wmode', 'opaque',
      'movie', 'slickboard',
      'src', 'slickboard',
      'FlashVars', 'xml_source=/cgi-bin/gaugexml3.cgi%3Fcfg%3D'+cfg+'%26target%3D'+target,
      'id', 'my_board',
      'name', 'my_board',
      'menu', 'true',
      'allowFullScreen', 'false',
      'allowScriptAccess','sameDomain',
      'quality', 'high',
      'align', 'top',
      'pluginspage', 'https://www.macromedia.com/go/getflashplayer',
      'play', 'true',
      'devicefont', 'false'
      );
}

function graph(cfg,target) {
  AC_FL_RunContent(
      'codebase', 'https://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,45,0',
      'width', '600',
      'height', '250',
      'scale', 'noscale',
      'salign', 'TL',
      'bgcolor', '#cccccc',
      'wmode', 'opaque',
      'movie', 'slickboard',
      'src', 'slickboard',
      'FlashVars', 'xml_source=/cgi-bin/graphxml3.cgi%3Fcfg%3D'+cfg+'%26target%3D'+target,
      'id', 'my_board',
      'name', 'my_board',
      'menu', 'true',
      'allowFullScreen', 'false',
      'allowScriptAccess','sameDomain',
      'quality', 'high',
      'align', 'top',
      'pluginspage', 'https://www.macromedia.com/go/getflashplayer',
      'play', 'true',
      'devicefont', 'false'
      );
}

