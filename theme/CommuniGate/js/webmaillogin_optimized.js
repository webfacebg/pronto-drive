var webmailselectpanel;var webmailtimerpanel;var inited_webmailselect=0;var inited_webmailtimer=0;var webmailselect_off=1;var mailclient="horde";var mailcountdown=0;var FORM=new Array();function disable_webmailselect_autologin(){SetNvData("webmailclient","-1");update_autoload_links()}function webmailselect_setdefaultclient(a){if(NVData.webmailclient&&NVData.webmailclient==a){SetNvData("webmailclient","-1")}else{if(webmailclients[a]){SetNvData("webmailclient",a);document.getElementById("mailclientname").innerHTML=webmailclients[a].name;webmailtimer_show()}}update_autoload_links()}function webmailtimer_show(){var b=document.getElementById("webmailtimer-content");if(!b){alert("The 'webmailtimer-content' id is missing")}if(!YAHOO.util.Dom.hasClass(b,"mainpopbg")){b.className="mainpopbg content"}var a=document.getElementById("webmailtimer_win");a.style.display="block";b.style.display="block";webmailtimer_init();webmailtimerpanel.show();a.style.width=b.offsetWidth+6;a.style.height=b.offsetHeight+8}function webmailtimer_init(){if(inited_webmailtimer){return}var a=function(){this.submit()};var b=function(){SetNvData("webmailclient","-1");update_autoload_links();this.cancel()};webmailtimerpanel=new YAHOO.widget.Dialog("webmailtimer_win",{fixedcenter:true,constraintoviewport:true,underlay:"none",close:true,visible:false,draggable:true,modal:false,buttons:[{text:"Ok",handler:a,isDefault:true},{text:"Cancel",handler:b}]});webmailtimerpanel.render();inited_webmailtimer=1}function webmailselect_init(){webmailselectpanel=new YAHOO.widget.Panel("webmailselect_win",{fixedcenter:true,constraintoviewport:true,underlay:"none",close:true,visible:false,draggable:true,modal:false});webmailselectpanel.render();webmailselectpanel.beforeHideEvent.subscribe(handle_hide_webmailselect,webmailselectpanel,true);inited_webmailselect=1;for(var a in webmailclients){var b=document.getElementById(a+"_auto");b.style.display=""}}function handle_hide_webmailselect(b){var a=document.getElementById("webmailselect-content");if(!a){alert("The 'webmailselect-content' id is missing")}var c=document.getElementById("webmailselect_win");a.style.display="none";c.style.display="none"}function show_webmailselect(){var a=document.getElementById("webmailselect-content");if(!a){alert("The 'webmailselect-content' id is missing")}if(!YAHOO.util.Dom.hasClass(a,"mainpopbg")){a.className="mainpopbg content"}var b=document.getElementById("webmailselect_win");b.style.display="block";a.style.display="block";if(inited_webmailselect!=1){webmailselect_init()}webmailselectpanel.beforeHideEvent.subscribe(disable_countdown,webmailselectpanel,true);mailclient=NVData.webmailclient;begin_mail_countdown();webmailselectpanel.show();b.style.width=a.offsetWidth+6;b.style.height=a.offsetHeight+8}function begin_mail_countdown(){mailcountdown=(NVData.webmail_autoload_numseconds||5);mailcountdown_go()}function mailcountdown_go(){if(mailcountdown==-1){return}document.getElementById("mailclients").innerHTML="Loading "+webmailclients[mailclient].name+" in "+mailcountdown+" second(s).";mailcountdown--;if(mailcountdown<=0){var a=new Date();window.location.href=safeurl()+"?login=1&gotime="+a.getTime()}else{setTimeout(mailcountdown_go,1000)}}function disable_webmailselect(){disable_countdown();webmailselectpanel.hide()}function disable_countdown(){mailcountdown=-1}function enable_webmailselect(){webmailselect_on=1}function check_webmailselect(){if(webmailclients[NVData.webmailclient]){show_webmailselect()}}function safeurl(){var a=window.location.href.split("?");return a[0]}function safe_webmailselect_check(){parseForm();var f=3200;var a=FORM.gotime;var b=FORM.login;if(b){if(a&&webmailclients[NVData.webmailclient]){var e=new Date();var c=e.getTime();if((c-f)<a){setTimeout(function(){window.location.href=webmailclients[NVData.webmailclient].uri},500);return}else{update_autoload_links();return}}update_autoload_links();check_webmailselect()}else{update_autoload_links();return}}function update_autoload_links(){for(var b in webmailclients){var a=document.getElementById(b+"_auto").getElementsByTagName("a");if(NVData.webmailclient==b){document.getElementById(b+"_cell").className="autoload";a[0].innerHTML='<span class="disable_autoload">'+webmail_disable_link+"</span>"}else{document.getElementById(b+"_cell").className="";a[0].innerHTML='<span class="enable_autoload">'+webmail_enable_link+"</span>"}}}function parseForm(){var d=window.location.search.substring(1);var c=d.split("&");for(var b=0;b<c.length;b++){var f=c[b].indexOf("=");if(f>0){var a=c[b].substring(0,f);var e=c[b].substring(f+1);FORM[a]=e}}}YAHOO.util.Event.onDOMReady(function(){enable_webmailselect();safe_webmailselect_check()});