function sprintf(){if(!arguments||arguments.length<1||!RegExp){return}var k=arguments[0];var i=/([^%]*)%('.|0|\x20)?(-)?(\d+)?(\.\d+)?(%|b|c|d|u|f|o|s|x|X)(.*)/;var s=b=[],c=0,g=0;while(s=i.exec(k)){var j=s[1],p=s[2],t=s[3],o=s[4];var l=s[5],h=s[6],e=s[7];g++;if(h=="%"){d="%"}else{c++;if(c>=arguments.length){alert("Error! Not enough function arguments ("+(arguments.length-1)+", excluding the string)\nfor the number of substitution parameters in string ("+c+" so far).")}var f=arguments[c];var q="";if(p&&p.substr(0,1)=="'"){q=j.substr(1,1)}else{if(p){q=p}}var m=true;if(t&&t==="-"){m=false}var r=-1;if(o){r=parseInt(o)}var n=-1;if(l&&h=="f"){n=parseInt(l.substring(1))}var d=f;if(h=="b"){d=parseInt(f).toString(2)}else{if(h=="c"){d=String.fromCharCode(parseInt(f))}else{if(h=="d"){d=parseInt(f)?parseInt(f):0}else{if(h=="u"){d=Math.abs(f)}else{if(h=="f"){d=(n>-1)?Math.round(parseFloat(f)*Math.pow(10,n))/Math.pow(10,n):parseFloat(f)}else{if(h=="o"){d=parseInt(f).toString(8)}else{if(h=="s"){d=f}else{if(h=="x"){d=(""+parseInt(f).toString(16)).toLowerCase()}else{if(h=="X"){d=(""+parseInt(f).toString(16)).toUpperCase()}}}}}}}}}}k=j+d+e}return k}function bytes(a){return a}function kilobytes(a){return(a*1024)}function megabytes(a){return(a*1024*1024)}function gigabytes(a){return(a*1024*1024*1024)}function terabytes(a){return(a*1024*1024*1024*1024)}function petabytes(a){return(a*1024*1024*1024*1024*1024)}function exabytes(a){return(a*1024*1024*1024*1024*1024*1024)}function toPrecision(d,c){var a=c||2;var e=Math.round(d*Math.pow(10,a)).toString();var g=e.length-a;var f=e.substr(g,a);return e.substr(0,g)+(f.match("^0{"+a+"}$")?"":"."+f)}function toHumanSize(a){if(!a||isNaN(a)){return"unknown Bytes"}if(a<kilobytes(1)){return a+" Bytes"}if(a<megabytes(1)){return toPrecision((a/kilobytes(1)))+" KB"}if(a<gigabytes(1)){return toPrecision((a/megabytes(1)))+" MB"}if(a<terabytes(1)){return toPrecision((a/gigabytes(1)))+" GB"}if(a<petabytes(1)){return toPrecision((a/terabytes(1)))+" TB"}if(a<exabytes(1)){return toPrecision((a/petabytes(1)))+" PB"}return toPrecision((a/exabytes(1)))+" EB"}var thisuploader=0;var boxes=1;var sdlg;var createdlg=0;var asyncRequests=[];var uploadKeys=[];var emptyCount={};var tNotice;var tNoticeDialog;var tNoticetimeout;var status_timeout;var finished_uploads={};var windowo=window.opener;var thiswindow=window;var windowcloser=function(){thiswindow.close()};var INITIAL_UPLOAD_STATUS_DELAY=3000;var UPLOAD_STATUS_INTERVAL=2000;function gobacktodir(a){if(windowo&&windowo.updateFileList){show_loading("Waiting for File Manager to Refresh");setTimeout(windowcloser,10000);windowo.updateFileList(a,0,windowcloser);return false}else{return true}}function safeencode(e){var d=encodeURIComponent(e);var a=-1;var c="";for(var f=0;f<d.length;f++){if(a>=0){a++}if(a>=3){a=-1}if(a==1||a==2){c+=d.substring(f,f+1).toLowerCase()}else{c+=d.substring(f,f+1)}if(d.substring(f,f+1)=="%"){a=0}}return c.replace("(","%28").replace(")","%29").replace(",","%2c")}function adduploader(){var f=0;var e=YAHOO.util.Dom.get("uploaders");if(e.hasChildNodes()){f+=e.childNodes.length}var a=DOM.get("uploaderhtml_template").text.trim();var c=YAHOO.lang.substitute(a,{thisid_html:f});var d=document.createElement("div");d.id="uploader"+f;d.innerHTML=c;e.appendChild(d)}function uploadcallbackfail(a){if(!a){return}window.status_timeout=setTimeout("updatefilestatus("+a.argument.thisid+")",UPLOAD_STATUS_INTERVAL)}function uploadcallback(d){if(!d){return}var k=d.responseXML.documentElement;if(k==null||d.responseText==""){if(!emptyCount[uploadKeys[d.argument.thisid]]){emptyCount[uploadKeys[d.argument.thisid]]=0}emptyCount[uploadKeys[d.argument.thisid]]+=1;if(emptyCount[uploadKeys[d.argument.thisid]]>=30){updatefilestatusHTML(d.argument.thisid,g,"unknown",p,0,0,0,1,"Unknown error or disk quota exceeded.");return}window.status_timeout=setTimeout("updatefilestatus("+d.argument.thisid+")",UPLOAD_STATUS_INTERVAL);debug("no xml");return}var m=k.getElementsByTagName("fileupload");var n=k.getAttribute("size");var e=toHumanSize(n);var p=0;var j=0;var f=0;var g;var a=k.getElementsByTagName("file");if(a.length>0){var g=a[a.length-1].getElementsByTagName("name");var l=a[a.length-1].getElementsByTagName("error");if(l.length>0){var c=l[l.length-1].getAttribute("failreason");var q=l[l.length-1].getAttribute("failmsg");updatefilestatusHTML(d.argument.thisid,g,(n||"unknown"),p,0,0,0,1,q);return}var h=a[a.length-1].getElementsByTagName("progress");if(h.length>0){p=h[h.length-1].getAttribute("complete");j=h[h.length-1].getAttribute("bytes");f=h[h.length-1].getAttribute("bps")}}else{debug("no files");window.status_timeout=setTimeout("updatefilestatus("+d.argument.thisid+")",UPLOAD_STATUS_INTERVAL);return}var i=0;if(n>0&&j){i=Math.floor((j/n)*100)}else{i=100}updatefilestatusHTML(d.argument.thisid,g,n,p,j,f,i);if(p!=1){window.status_timeout=setTimeout("updatefilestatus("+d.argument.thisid+")",INITIAL_UPLOAD_STATUS_DELAY)}}var updates={};function updatefilestatusHTML(f,y,k,g,d,u,h,j,e){if(updates[f]){updates[f].count++;updates[f].total_bps+=parseFloat(u)}else{updates[f]={count:1,total_bps:parseFloat(u)}}var w=updates[f].total_bps/updates[f].count;var s=YAHOO.util.Dom.get("progresstxt"+f);var A=Math.ceil((h/100)*200);var p=Math.floor((1-(h/100))*200);var m=YAHOO.util.Dom.get("progress-image"+f);var c=YAHOO.util.Dom.get("progress-complete"+f);var x=YAHOO.util.Dom.get("progress-incomplete"+f);var a;var n=toHumanSize(w);debug("niceBps"+n);if(w>0){var r=sprintf("%.2f",((k-d)/w));var v=parseInt(r%60);var q=parseInt(r/60);a=q+"m "+v+"s"}else{if(!g&&!j){return}}var z;if(g||j){show_finished_upload(f,k,!j,e)}else{if(!finished_uploads[f]){DOM.setStyle("progress-image"+f,"width",h+"%");var i=toHumanSize(k);var t=toHumanSize(d);var o=YAHOO.util.Dom.get("file"+f).value;var l=o.split("/");var y=l[l.length-1];if(finished_uploads[f]){return}z=y+": "+t+" / "+i+" ("+h+"%) complete<br />ETA ~ "+a+" @ "+n+"/s";debug("new html is"+z);s.innerHTML=z}}}function updatefilestatus(d){var a={success:uploadcallback,failure:uploadcallbackfail,timeout:10000,argument:{thisid:d}};var c=CPANEL.security_token+"/uploadstatus/?uploadid="+uploadKeys[d];var e=asyncRequests.length;asyncRequests[e]=YAHOO.util.Connect.asyncRequest("GET",c,a,null)}function startupload(f,a){var c=(f.id.split("file"))[1];var g=Math.random()*9999999;var j=Math.floor(g);uploadKeys[c]=uploadkey+j;var e=f.form;var i=e.overwrite;if(a||YAHOO.util.Dom.get("overwrite_checkbox").checked){i.value="1"}else{i.value="0"}var h=document.fmode;e.permissions.value="0"+h.u.value+h.g.value+h.w.value;e["cpanel-trackupload"].value=uploadKeys[c];DOM.get("upload_queue").appendChild(DOM.get("uploaderstatus"+c));YAHOO.util.Dom.get("uploaderstatus"+c).style.display="block";var d=DOM.get("ut"+c);d.onload=function(){d.onload=function(){};var l=CPANEL.util.get_text_content(d.contentDocument.documentElement);var n=YAHOO.lang.JSON.parse(l);if(n){var k,m;try{k=n.cpanelresult.data[0].uploads[0];m=n.cpanelresult.data[0].diskinfo}catch(o){}if(k&&!finished_uploads[c]){show_finished_upload(c,k.size,parseInt(k.status),k.reason)}if(m){CPANEL.util.set_text_content("file_upload_remain",m.file_upload_remain_humansize)}}};e.submit();e.style.display="none";f.disabled=true;adduploader();window.status_timeout=setTimeout(function(){updatefilestatus(c)},INITIAL_UPLOAD_STATUS_DELAY)}function show_finished_upload(d,f,m,h){if(finished_uploads[d]){return}clearTimeout(window.status_timeout);finished_uploads[d]=true;DOM.addClass("uploaderstatus"+d,"complete");DOM.get("uploaderstatus"+d).title=LANG.click_to_close;YAHOO.util.Event.on("uploaderstatus"+d,"click",function c(){YAHOO.util.Event.removeListener(this,"click",c);this.parentNode.removeChild(this)});var j=toHumanSize(f);var i=YAHOO.util.Dom.get("file"+d).value;var e=i.split("/");var g=e[e.length-1].html_encode();var l=YAHOO.util.Dom.get("progresstxt"+d);var k=g+": "+j+" complete"+(!m?(" FAILED! :"+h):"");l.innerHTML=k;var a=YAHOO.util.Dom.get("progress-image"+d);a.style.backgroundImage="url("+DOM.get("progress_bar_done_prototype").src+")";DOM.setStyle("progress-image"+d,"width","100%")}function parsexmlStat(c){var m=c.responseXML.documentElement;if(m==null){alert("There was a problem fetching the file list! Please reload and try again.");return}var h=m.getElementsByTagName("file");if(!h||!h[0]){startupload(c.argument.file_input);return}var g=0;var j=1;if(!h[g].getElementsByTagName("mtime")[0].firstChild){j=0}else{if(!h[g].getElementsByTagName("mtime")[0].firstChild.nodeValue){j=0}}thisfile_input=c.argument.file_input;var n=YAHOO.util.Dom.get("overwrite_checkbox").checked;if(j&&n==false){var e=unescape(h[g].getElementsByTagName("name")[0].firstChild.nodeValue);var f=unescape(h[g].getElementsByTagName("mtime")[0].firstChild.nodeValue);var l=new Date(f*1000);var p=l.toLocaleString();var k=function(){this.hide();startupload(thisfile_input,1)};var a=function(){this.hide()};var d=YAHOO.lang.substitute(DOM.get("already_exists_template").text.trim(),{file_html:e.html_encode(),last_mod_html:p.html_encode()});if(!createdlg){sdlg=new YAHOO.widget.SimpleDialog("sdlg1",{width:"450px",fixedcenter:true,visible:false,modal:true,draggable:false,close:true,constraintoviewport:true,effect:{effect:CPANEL.animate.ContainerEffect.FADE_MODAL,duration:0.25},buttons:[{text:LANG.yes,handler:k,isDefault:true},{text:LANG.no,handler:a}]});sdlg.setHeader("<div class='lt'></div>&nbsp;<div class='rt'></div>");createdlg=1}sdlg.cfg.queueProperty("text",d);sdlg.render();sdlg.show()}else{startupload(c.argument.file_input)}}function xmlStaterrorFunction(a){if(!a){return}alert("Error: "+a.status+" "+a.statusText+" There was a problem fetching the files information: "+a.responseText)}function uploadfile(h){var f=h.value;var j=String.fromCharCode(92);var c="/";if(f.indexOf(j)>-1){c=j}var d=f.split(c);var e=safeencode(d[d.length-1]);var i={success:parsexmlStat,failure:xmlStaterrorFunction,argument:{file_input:h}};var a="live_statfiles.xml?files="+safeencode(dir)+"%2f"+e;var g=asyncRequests.length;asyncRequests[g]=YAHOO.util.Connect.asyncRequest("GET",a,i,null)}function debug(a){return false}function setuppanels(){window.waitpanel=new YAHOO.widget.Panel("waitpanel",{width:"252px",fixedcenter:true,close:false,draggable:false,modal:true,visible:false,effect:{effect:CPANEL.animate.ContainerEffect.FADE_MODAL,duration:0.25}})}function show_loading(d,a){waitpanel.setHeader(d);var c='<img src="img/yui/rel_interstitial_loading.gif" alt="" />';if(a){waitpanel.setBody(a+"<br />"+c)}else{waitpanel.setBody(c)}waitpanel.render(document.body);waitpanel.show()}function initialize(){adduploader();setuppanels();var c=DOM.get("chmod");var a=document.fmode;a.onsubmit=function(){return false};a.ur.checked=a.gr.checked=a.wr.checked=true;a.uw.checked=true;calcperm();DOM.removeClass("chmodtbl","sortable");c.parentNode.replaceChild(a,c);YAHOO.util.Event.throwErrors=true}YAHOO.util.Event.onDOMReady(initialize);var use_fast_proto=1;function cpanel_api1(){var h=cpanel_api1.arguments;var c=h[0];var a=h[1];var d=h[2];var e=h.length;var k={success:cpanel_api1_parser,argument:c};var j;if(use_fast_proto){j="cpanel_xmlapi_module="+encodeURIComponent(a)+"&cpanel_xmlapi_func="+encodeURIComponent(d)+"&cpanel_xmlapi_apiversion=1";var g=0;for(var f=3;f<e;f++){j+="&arg-"+g+"="+encodeURIComponent(h[f]);g++}}else{j="xmlin=<cpanelaction><apiversion>1</apiversion><module>"+a+"</module><func>"+d+"</func>";for(var f=3;f<e;f++){j+="<args>"+h[f]+"</args>"}j+="</cpanelaction>"}if(j.length<2000){YAHOO.util.Connect.asyncRequest("GET",CPANEL.security_token+"/xml-api/cpanel?"+j,k)}else{YAHOO.util.Connect.asyncRequest("POST",CPANEL.security_token+"/xml-api/cpanel",k,j)}}function cpanel_api1_parser(h){var g=h.argument;var d=h.responseXML;var c=d.getElementsByTagName("cpanelresult")[0];var e=c.getElementsByTagName("data")[0];var a=e.getElementsByTagName("result")[0];var f;if(a.firstChild){f=a.firstChild.nodeValue}if(g){g(f)}}function cpanel_api2(){var a=cpanel_api2.arguments;var g=a[0];var d=a[1];var e=a[2];var h=a.length;var j={success:cpanel_api2_parser,argument:g};var f;if(use_fast_proto){f="cpanel_xmlapi_module="+encodeURIComponent(d)+"&cpanel_xmlapi_func="+encodeURIComponent(e)+"&cpanel_xmlapi_apiversion=2";for(var c=3;c<h;c+=2){f+="&"+encodeURIComponent(a[c])+"="+encodeURIComponent(a[c+1])}}else{f="xmlin=<cpanelaction><apiversion>2</apiversion><module>"+d+"</module><func>"+e+"</func><args>";for(var c=3;c<h;c+=2){f+="<"+a[c]+">"+a[c+1]+"</"+a[c]+">"}f+="</args></cpanelaction>"}if(f.length<2000){YAHOO.util.Connect.asyncRequest("GET",CPANEL.security_token+"/xml-api/cpanel?"+f,j)}else{YAHOO.util.Connect.asyncRequest("POST",CPANEL.security_token+"/xml-api/cpanel",j,f)}}function cpanel_api2_parser(f){var e=f.argument;var c=f.responseXML;var a=c.getElementsByTagName("cpanelresult")[0];var d=a.getElementsByTagName("data");if(e){e(d)}}function cpanel_jsonapi1(){var h=cpanel_jsonapi1.arguments;var c=h[0];var a=h[1];var d=h[2];var e=h.length;var k={success:cpanel_jsonapi1_parser,failure:c,argument:c};var j="cpanel_jsonapi_module="+encodeURIComponent(a)+"&cpanel_jsonapi_func="+encodeURIComponent(d)+"&cpanel_jsonapi_apiversion=1";var g=0;for(var f=3;f<e;f++){j+="&arg-"+g+"="+encodeURIComponent(h[f]);g++}if(j.length<2000){YAHOO.util.Connect.asyncRequest("GET",CPANEL.security_token+"/json-api/cpanel?"+j,k)}else{YAHOO.util.Connect.asyncRequest("POST",CPANEL.security_token+"/json-api/cpanel",k,j)}}function cpanel_jsonapi1_parser(d){var c=d.argument;var a=fastJsonParse(d.responseText);if(c){c(a.cpanelresult.data.result)}}function cpanel_jsonapi2(){var a=cpanel_jsonapi2.arguments;var g=a[0];var d=a[1];var e=a[2];var h=a.length;var j={success:cpanel_jsonapi2_parser,failure:g,argument:g};var f="cpanel_jsonapi_module="+encodeURIComponent(d)+"&cpanel_jsonapi_func="+encodeURIComponent(e)+"&cpanel_jsonapi_apiversion=2";for(var c=3;c<h;c+=2){f+="&"+encodeURIComponent(a[c])+"="+encodeURIComponent(a[c+1])}if(f.length<2000){YAHOO.util.Connect.asyncRequest("GET",CPANEL.security_token+"/json-api/cpanel?"+f,j)}else{YAHOO.util.Connect.asyncRequest("POST",CPANEL.security_token+"/json-api/cpanel",j,f)}}function cpanel_jsonapi2_parser(d){var c=d.argument;var a=fastJsonParse(d.responseText);if(c){c(a.cpanelresult.data)}}var NativeJson=Object.prototype.toString.call(this.JSON)==="[object JSON]"&&this.JSON;function fastJsonParse(c,a){return NativeJson?NativeJson.parse(c,a):YAHOO.lang.JSON.parse(c,a)};