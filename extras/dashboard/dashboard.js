// Set these to the location of the CGI bins, and set ispublic to '-public'
// if you are using the no-password setup (recommended)
// Note that these cannot have a hostname else the XSS protection stops them
var nagioscgi  = '/nagios/cgi-bin/';
var mrtgcgi    = '/cgi-bin/';
var dashboardcgi = '/cgi-bin/';
var ispublic   = '-public';
var licensekey = '';
//
var requiredMajorVersion = 9;
var requiredMinorVersion = 0;
var requiredRevision = 45;
if (AC_FL_RunContent == 0 || DetectFlashVer == 0) {
	alert("This page requires AC_RunActiveContent.js.");
} else {
	var hasRightVersion = DetectFlashVer(requiredMajorVersion, requiredMinorVersion, requiredRevision);
	if(!hasRightVersion) { 
		var alternateContent = '<B>This content requires the Adobe Flash Player.</B> '
		+ '<u><a href=http://www.macromedia.com/go/getflash/>Get Flash</a></u>.';
		document.write(alternateContent); 
	}
}
function bars(cfg,target) {
  var n = new Date();
  AC_FL_RunContent(
      'codebase', 'https://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,45,0',
      'width', '200',
      'height', '250',
      'scale', 'noscale',
      'salign', 'TL',
      'bgcolor', '#cccccc',
      'wmode', 'opaque',
      'movie', 'slickboard',
      'src', 'slickboard',
      'FlashVars', 'xml_source='+mrtgcgi+'/gaugexml3'+ispublic+'.cgi%3Fcfg%3D'+cfg+'%26target%3D'+target+'%26url%3D'+mrtgcgi+'/gaugexml3'+ispublic+'.cgi%26license%3D'+encodeURIComponent(licensekey)+'%26width%3D200%26height%3D250%26type%3Dbars%26t%3D1'+n.getTime(),
      'id', 'my_board',
      'name', 'my_board',
      'menu', 'true',
      'allowFullScreen', 'false',
      'allowScriptAccess','always',
      'quality', 'high',
      'align', 'top',
      'pluginspage', 'https://www.macromedia.com/go/getflashplayer',
      'play', 'true',
      'devicefont', 'false'
      );
}
function gauge(cfg,target) {
  var n = new Date();
  AC_FL_RunContent(
      'codebase', 'https://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,45,0',
      'width', '200',
      'height', '250',
      'scale', 'noscale',
      'salign', 'TL',
      'bgcolor', '#cccccc',
      'wmode', 'opaque',
      'movie', 'slickboard',
      'src', 'slickboard',
      'FlashVars', 'xml_source='+mrtgcgi+'/gaugexml3'+ispublic+'.cgi%3Fcfg%3D'+cfg+'%26target%3D'+target+'%26url%3D'+mrtgcgi+'/gaugexml3'+ispublic+'.cgi%26license%3D'+encodeURIComponent(licensekey)+'%26width%3D200%26height%3D250%26t%3D1'+n.getTime(),
      'id', 'my_board',
      'name', 'my_board',
      'menu', 'true',
      'allowFullScreen', 'false',
      'allowScriptAccess','always',
      'quality', 'high',
      'align', 'top',
      'pluginspage', 'https://www.macromedia.com/go/getflashplayer',
      'play', 'true',
      'devicefont', 'false'
      );
}

function graph(cfg,target) {
  var n = new Date();
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
      'FlashVars', 'xml_source='+mrtgcgi+'/graphxml3'+ispublic+'.cgi%3Fcfg%3D'+cfg+'%26target%3D'+target+'%26url%3D'+mrtgcgi+'/graphxml3'+ispublic+'.cgi%26license%3D'+encodeURIComponent(licensekey)+'%26width%3D600%26height%3D250%26t%3D1'+n.getTime(),
      'id', 'my_board',
      'name', 'my_board',
      'menu', 'true',
      'allowFullScreen', 'false',
      'allowScriptAccess','always',
      'quality', 'high',
      'align', 'top',
      'pluginspage', 'https://www.macromedia.com/go/getflashplayer',
      'play', 'true',
      'devicefont', 'false'
      );
}
function nagiosgroup(hostgroupname,width,height) {
  var n = new Date();
  AC_FL_RunContent(
      'codebase', 'https://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,45,0',
      'width', (width?width:600),
      'height', (height?height:250),
      'scale', 'noscale',
      'salign', 'TL',
      'bgcolor', '#cccccc',
      'wmode', 'opaque',
      'movie', 'slickboard',
      'src', 'slickboard',
      'FlashVars', 'xml_source='+nagioscgi+'/nagiosxml'+ispublic+'.cgi%3Fhostgroup%3D'+hostgroupname+'%26width%3D'+width+'%26height%3D'+height+'%26url%3D'+nagioscgi+'/nagiosxml'+ispublic+'.cgi%26license%3D'+encodeURIComponent(licensekey)+'%26t%3D1'+n.getTime(),
      'id', 'my_board',
      'name', 'my_board',
      'menu', 'true',
      'allowFullScreen', 'false',
      'allowScriptAccess','always',
      'quality', 'high',
      'align', 'top',
      'pluginspage', 'https://www.macromedia.com/go/getflashplayer',
      'play', 'true',
      'devicefont', 'false'
      );
}
function nagioshost(hostname,width,height) {
  var n = new Date();
  AC_FL_RunContent(
      'codebase', 'https://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,45,0',
      'width', (width?width:600),
      'height', (height?height:250),
      'scale', 'noscale',
      'salign', 'TL',
      'bgcolor', '#cccccc',
      'wmode', 'opaque',
      'movie', 'slickboard',
      'src', 'slickboard',
      'FlashVars', 'xml_source='+nagioscgi+'/nagiosxml'+ispublic+'.cgi%3Fhost%3D'+hostname+'%26width%3D'+width+'%26height%3D'+height+'%26url='+nagioscgi+'/nagiosxml'+ispublic+'.cgi%26license%3D'+encodeURIComponent(licensekey)+'%26t%3D1'+n.getTime(),
      'id', 'my_board',
      'name', 'my_board',
      'menu', 'true',
      'allowFullScreen', 'false',
      'allowScriptAccess','always',
      'quality', 'high',
      'align', 'top',
      'pluginspage', 'https://www.macromedia.com/go/getflashplayer',
      'play', 'true',
      'devicefont', 'false'
      );
}
function applet(url,width,height) {
  AC_FL_RunContent(
      'codebase', 'https://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,45,0',
      'width', width,
      'height', height,
      'scale', 'noscale',
      'salign', 'TL',
      'bgcolor', '#cccccc',
      'wmode', 'opaque',
      'movie', 'slickboard',
      'src', 'slickboard',
      'FlashVars', 'xml_source='+encodeURIComponent(url),
      'id', 'my_board',
      'name', 'my_board',
      'menu', 'true',
      'allowFullScreen', 'false',
      'allowScriptAccess','always',
      'quality', 'high',
      'align', 'top',
      'pluginspage', 'https://www.macromedia.com/go/getflashplayer',
      'play', 'true',
      'devicefont', 'false'
      );
}
// --------------------------------------------------------------
// Now the dashboard object
//
// Example:
// var d = new Dashboard(1000,750);
// d.addGauge(0,0,'file.cfg','targetname');
// d.addGraph(200,0,'file.cfg','targetname');
// d.addNagiosHost(0,250,600,250,'hostname');
// d.write;
//

function Dashboard(width,height) {
	this.widgets = 0;
	this.optionstring = '';
	if(width < 50) { width = 200; }
	if(height < 50) { height = 250; }
	this.width = width;
	this.height = height;	
	this.license = licensekey;
	this.mrtgcgi = mrtgcgi;
	this.nagioscgi = nagioscgi;
	this.ispublic = ispublic;
	this.bgcolor = '#cccccc';
	this.title = 'Dashboard';
	
	this.setHeight = function(height) {
		this.height = height;
	}
	this.setWidth = function(width) {
		this.width = width;
	}
	this.setTitle = function(title) {
		this.title = title;
	}
	this.write = function() {
		var xmlsrc;
		xmlsrc = dashboardcgi+'/dashboardxml.cgi?widgets='+this.widgets
			+'&width='+width+'&height='+height
			+'&license='+encodeURIComponent(this.license)
			+'&title='+encodeURIComponent(this.title)
			+this.optionstring;

		AC_FL_RunContent(
      'codebase', 'https://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,45,0',
      'width', this.width,
      'height', this.height,
      'scale', 'noscale',
      'salign', 'TL',
      'bgcolor', this.bgcolor,
      'wmode', 'opaque',
      'movie', 'slickboard',
      'src', 'slickboard',
      'FlashVars', 'xml_source='+encodeURIComponent(xmlsrc),
      'id', 'my_board',
      'name', 'my_board',
      'menu', 'true',
      'allowFullScreen', 'false',
      'allowScriptAccess','always',
      'quality', 'high',
      'align', 'top',
      'pluginspage', 'https://www.macromedia.com/go/getflashplayer',
      'play', 'true',
      'devicefont', 'false'
      );
	}
	this.addWidget = function(x,y,w,h,url) {
		if((x>=0)&&(y>=0)&&(x<=this.width)&&(y<=this.height)) {
			this.widgets = this.widgets + 1;
			this.optionstring = this.optionstring 
				+'&url'+this.widgets+'='+encodeURIComponent(url)
				+'&x'+this.widgets+'='+x
				+'&y'+this.widgets+'='+y
				+'&width'+this.widgets+'='+w
				+'&height'+this.widgets+'='+h;
		} else {
			alert('Dashboard widget at ['+x+','+y+'] outside of dashboard area!');
		}
	}
	this.addGauge = function(x,y,device,target) {
		this.addWidget(x,y,200,250,
      		this.mrtgcgi+'/gaugexml3'+this.ispublic+'.cgi?object=1&cfg='+device
			+'&target='+target+'&width=200&height=250'
			+'&url='+this.mrtgcgi+'/gaugexml3'+this.ispublic+'.cgi&license='
			+this.license);
	}
	this.addBars = function(x,y,device,target) {
		this.addWidget(x,y,200,250,
      		this.mrtgcgi+'/gaugexml3'+this.ispublic+'.cgi?object=1&cfg='+device
			+'&target='+target+'&width=200&height=250&type=bars'
			+'&url='+this.mrtgcgi+'/gaugexml3'+this.ispublic+'.cgi&license='
			+this.license);
	}
	this.addGraph = function(x,y,device,target) {
		this.addWidget(x,y,600,250,
      		this.mrtgcgi+'/graphxml3'+this.ispublic+'.cgi?object=1&cfg='+device
			+'&target='+target+'&width=600&height=250'
			+'&url='+this.mrtgcgi+'/graphxml3'+this.ispublic+'.cgi&license='
			+this.license);
	}
	this.addNagiosGroup = function(x,y,w,h,hostgroup) {
        this.addWidget(x,y,w,h, 
			this.nagioscgi+'/nagiosxml'+this.ispublic+'.cgi?object=1&hostgroup='
			+hostgroup+'&width='+w+'&height='+h+'&url='+nagioscgi+'/nagiosxml'
			+ispublic+'.cgi&license='+this.license);
	}
	this.addNagiosHost = function(x,y,w,h,hostname) {
        this.addWidget(x,y,w,h, 
			this.nagioscgi+'/nagiosxml'+this.ispublic+'.cgi?object=1&host='
			+hostname+'&width='+w+'&height='+h+'&url='+nagioscgi+'/nagiosxml'
			+ispublic+'.cgi&license='+this.license);
	}
}

