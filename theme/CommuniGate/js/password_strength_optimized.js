function getPasswordStrength(c){var l=["cpanel","cpanel1","server","hosting","linux","website","123456","porsche","firebird","prince","rosebud","password","guitar","butter","beach","jaguar","12345678","chelsea","united","amateur","great","1234","black","turtle","7777777","cool","pussy","diamond","steelers","muffin","cooper","12345","nascar","tiffany","redsox","1313","dragon","jackson","zxcvbn","star","scorpio","qwerty","cameron","tomcat","testing","mountain","696969","654321","golf","shannon","madison","mustang","computer","bond007","murphy","987654","letmein","amanda","bear","frank","brazil","baseball","wizard","tiger","hannah","lauren","master","xxxxxxxx","doctor","dave","japan","michael","money","gateway","eagle1","naked","football","phoenix","gators","11111","squirt","shadow","mickey","angel","mother","stars","monkey","bailey","junior","nathan","apple","abc123","knight","thx1138","raiders","alexis","pass","iceman","porno","steve","aaaa","fuckme","tigers","badboy","forever","bonnie","6969","purple","debbie","angela","peaches","jordan","andrea","spider","viper","jasmine","harley","horny","melissa","ou812","kevin","ranger","dakota","booger","jake","matt","iwantu","aaaaaa","1212","lovers","qwertyui","jennifer","player","flyers","suckit","danielle","hunter","sunshine","fish","gregory","beaver","fuck","morgan","porn","buddy","4321","2000","starwars","matrix","whatever","4128","test","boomer","teens","young","runner","batman","cowboys","scooby","nicholas","swimming","trustno1","edward","jason","lucky","dolphin","thomas","charles","walter","helpme","gordon","tigger","girls","cumshot","jackie","casper","robert","booboo","boston","monica","stupid","access","coffee","braves","midnight","shit","love","xxxxxx","yankee","college","saturn","buster","bulldog","lover","baby","gemini","1234567","ncc1701","barney","cunt","apples","soccer","rabbit","victor","brian","august","hockey","peanut","tucker","mark","3333","killer","john","princess","startrek","canada","george","johnny","mercedes","sierra","blazer","sexy","gandalf","5150","leather","cumming","andrew","spanky","doggie","232323","hunting","charlie","winter","zzzzzz","4444","kitty","superman","brandy","gunner","beavis","rainbow","asshole","compaq","horney","bigcock","112233","fuckyou","carlos","bubba","happy","arthur","dallas","tennis","2112","sophie","cream","jessica","james","fred","ladies","calvin","panties","mike","johnson","naughty","shaved","pepper","brandon","xxxxx","giants","surfer","1111","fender","tits","booty","samson","austin","anthony","member","blonde","kelly","william","blowme","boobs","fucked","paul","daniel","ferrari","donald","golden","mine","golfer","cookie","bigdaddy","king","summer","chicken","bronco","fire","racing","heather","maverick","penis","sandra","5555","hammer","chicago","voyager","pookie","eagle","yankees","joseph","rangers","packers","hentai","joshua","diablo","birdie","einstein","newyork","maggie","sexsex","trouble","dolphins","little","biteme","hardcore","white","redwings","enter","666666","topgun","chevy","smith","ashley","willie","bigtits","winston","sticky","thunder","welcome","bitches","warrior","cocacola","cowboy","chris","green","sammy","animal","silver","panther","super","slut","broncos","richard","yamaha","qazwsx","8675309","private","fucker","justin","magic","zxcvbnm","skippy","orange","banana","lakers","nipples","marvin","merlin","driver","rachel","power","blondes","michelle","marine","slayer","victoria","enjoy","corvette","angels","scott","asdfgh","girl","bigdog","fishing","2222","vagina","apollo","cheese","david","asdf","toyota","parker","matthew","maddog","video","travis","qwert","121212","hooters","london","hotdog","time","patrick","wilson","7777","paris","sydney","martin","butthead","marlboro","rock","women","freedom","dennis","srinivas","xxxx","voodoo","ginger","fucking","internet","extreme","magnum","blowjob","captain","action","redskins","juice","nicole","bigdick","carter","erotic","abgrtyu","sparky","chester","jasper","dirty","777777","yellow","smokey","monster","ford","dreams","camaro","xavier","teresa","freddy","maxwell","secret","steven","jeremy","arsenal","music","dick","viking","11111111","access14","rush2112","falcon","snoopy","bill","wolf","russia","taylor","blue","crystal","nipple","scorpion","111111","eagles","peter","iloveyou","rebecca","131313","winner","pussies","alex","tester","123123","samantha","cock","florida","mistress","bitch","house","beer","eric","phantom","hello","miller","rocket","legend","billy","scooter","flower","theman","movie","6666","please","jack","oliver","success","albert"];var t=0;var r=0;var k=0;var g=0;var A=0;var v=0;var q=0;var h=0;var n=0;var e=0;var b=0;var m=0;var w=0;var s=0;t=c.length;var x=false;for(var z=0;z<t;z++){var a=c.charAt(z);var u=new RegExp(/[A-Z]/);if(a.match(u)){r++;if(x){if(x.match(u)){b++}}}var f=new RegExp(/[a-z]/);if(a.match(f)){k++;if(x){if(x.match(f)){m++}}}var p=new RegExp(/\d/);if(a.match(p)){g++;if(x){if(x.match(p)){w++}}}if(a.match(new RegExp(/\W/))){A++}if(z!=0&&z!=t-1){if(a.match(new RegExp(/\d/))||a.match(new RegExp(/\W/))){v++}}for(var y=0;y<t;y++){if(a==c.charAt(y)&&y!=z){e++}}x=a}if(g==0&&A==0){h=k+r}if(k==0&&r==0&&A==0){n=g}var o=0;if(r!=0){o++}if(k!=0){o++}if(g!=0){o++}if(A!=0){o++}if(t>=8&&o>=3){q=t}for(var z=0;z<l.length;z++){var d=new RegExp(l[z],"i");if(c.match(d)){s++}}var B=0;B+=t*4;B+=(t-r)*2;B+=(t-k)*2;B+=g*4;B+=A*6;B+=v*2;B+=q*2;B-=h;B-=n;B-=e*(e-1);B-=b*2;B-=m*2;B-=w*2;B-=s*(B/5);B=parseInt(B);if(B<0){B=0}if(B>100){B=100}return B}var tip_box_has_focus=0;var pw_box_has_focus=0;var attached_form;var pwstrapp;var attached_pwbox={};var password_str_handle_validate=1;var pwminstrength=0;var pwminstrength_fail_txt="Sorry, the password you selected cannot be used because it is too weak and would be too easy to crack.  Please select a password with strength rating of % or higher.";var pwminstrength_tip='You can increase the strength of your password by adding UPPER CASE, numbers, and symbol characters.  You should avoid using words that are in the dictionary as <a href="http://en.wikipedia.org/wiki/Password_cracking" target="_blank">crackers</a> usually start with these first.  Currently the system requires you use a password with a strength rating of % or greater.';function hide_password_tip_panel_if_no_box_focus(){if(!tip_box_has_focus&&!pw_box_has_focus){hide_password_tip_panel()}}function ensurePwStrength(c,a){var b=""+a.value;var d=getPasswordStrength(b);if(d<pwminstrength){YAHOO.util.Event.stopEvent(c);alert(pwminstrength_fail_txt.replace("%",pwminstrength))}}function updatePasswordStrength_new(g,j,o,s){var f=""+g.value;if(attached_pwbox[g.id]!=1){YAHOO.util.Event.addFocusListener(g,function(i){pw_box_has_focus=1});YAHOO.util.Event.addBlurListener(g,function(i){pw_box_has_focus=0;setTimeout(hide_password_tip_panel_if_no_box_focus,250)});attached_pwbox[g.id]=1}if(pwstrapp&&pwminstrengthapps[pwstrapp]){pwminstrength=pwminstrengthapps[pwstrapp]}if(!attached_form){init_passtip_dialog();var k=g.form;if(k&&k.action&&k.action.length>3){if(self.register_validator){register_validator("func",function(i){var w=i[0];var x=""+w.value;var y=getPasswordStrength(x);if(y<pwminstrength){return false}else{return true}},[g],pwminstrength_fail_txt.replace("%",pwminstrength))}else{YAHOO.util.Event.addListener(k,"submit",function(i){ensurePwStrength(i,g)},this,true)}}var r=document.getElementById("password_tip_panel");if(r){YAHOO.util.Event.addBlurListener(r,function(i){tip_box_has_focus=0});YAHOO.util.Event.addListener(r,"click",function(i){tip_box_has_focus=1});YAHOO.util.Event.addFocusListener(r,function(i){tip_box_has_focus=1});var n=r.getElementsByTagName("a");for(var u=0;u<n.length;u++){YAHOO.util.Event.addBlurListener(n[u],function(i){tip_box_has_focus=0});YAHOO.util.Event.addListener(n[u],"click",function(i){tip_box_has_focus=1});YAHOO.util.Event.addFocusListener(n[u],function(i){tip_box_has_focus=1})}}attached_form=1}var l=getPasswordStrength(f);var q=(parseInt(l/10)*10);var e=document.getElementById(j);if(!e){return;alert("Password Strength Display Element Missing")}var p=e.getElementsByTagName("div");var a=p[0].getElementsByTagName("div");var t=pwminstrength>0?pwminstrength:100;var m=l<t?l:t;var d=parseInt((m/t)*3);a[0].className="pass_bar_base pass_bar_"+q+" pass_bar_color_"+(d?d:1);var c=1;if(o&&o.text>-1){c=o.text}var b=p[c];if(b&&self.pass_strength_phrases){if(pwminstrength>50&&l>=50&&l<pwminstrength){q=40}b.innerHTML=pass_strength_phrases[q]+" ("+l+"/100)"}var v;if(o&&o.rating>-1){v=o.rating}var h=p[v];if(h&&self.pass_strength_phrases){h.innerHTML="Strength: ("+l+")"}if(l<pwminstrength){if(!s){show_password_tip_panel()}if(password_str_handle_validate){YAHOO.util.Dom.addClass(g,"formverifyfailed")}}else{hide_password_tip_panel();if(password_str_handle_validate){YAHOO.util.Dom.removeClass(g,"formverifyfailed")}}}function updatePasswordStrength(f,e,c){var d=""+f.value;var h=getPasswordStrength(d);var i=(parseInt(h/10)*10);var a=document.getElementById(e);if(!a){return;alert("Password Strength Display Element Missing")}var g=a.getElementsByTagName("div");var b=0;var j=1;if(c&&c.text>-1){j=c.text}if(c&&c.image>-1){b=c.image}var l=g[b];l.id="ui-passbar-"+i;var k=g[j];if(k&&self.pass_strength_phrases){k.innerHTML=pass_strength_phrases[i]}}var password_tip_panel;var password_tip_panel_initted=0;var password_gen_panel;var password_gen_panel_initted=0;var password_use_panel;var password_use_panel_initted=0;var password_gen_pwbox;var password_gen_update_func;var did_password_gen=0;var chrsets={uppercase:[{start:65,end:90}],lowercase:[{start:97,end:122}],numbers:[{start:48,end:57}],symbols:[{start:33,end:47},{start:58,end:64},{start:123,end:126}]};var defaultallowedtxt=["lowercase","uppercase","numbers","symbols"];function get_chr_string(d){var a="";if(!chrsets[d]||!chrsets[d].length){return""}for(var c=0;c<chrsets[d].length;c++){for(var b=chrsets[d][c]["start"];b<=chrsets[d][c]["end"];b++){a+=String.fromCharCode(b)}}return a}function getrand(a){return Math.floor(Math.random()*a)}function generate_password(a,e,d){var c="";if(!e.length){e=defaultallowedtxt}for(var b=0;b<e.length;b++){c+=get_chr_string(e[b])}var g=d.split("");for(var b=0;b<g.length;b++){c=c.replace(g[b],"")}if(c.length==0){return""}var f="";while(f.length<a){f+=c.charAt(getrand(c.length))}return f}function open_usepass_dialog(a){init_usepass_dialog();document.getElementById("password_use_newpass").innerHTML=html_encode_str(a);password_use_panel.show()}function open_passgen_dialog(b,a){init_passgen_dialog();password_gen_pwbox=a;password_gen_update_func=b;password_gen_panel.show();if(!did_password_gen){dialogGeneratePass()}}function handlePassCancel(){password_gen_panel.hide()}function handlePassSubmit(){password_gen_panel.hide();var e=document.getElementById("dialogPassword");var f=document.getElementById(password_gen_pwbox);f.value=e.value;var a=[f];if(f.type=="password"){var c=0;var b=document.getElementsByTagName("input");for(var d=0;d<b.length;d++){if(c){if(b[d].type=="password"){a.push(b[d]);b[d].value=e.value;break}else{if(b[d].type=="text"){break}}}else{if(b[d].id==password_gen_pwbox){c=1}}}}password_gen_update_func();if(self.do_validate){for(var d=0;d<a.length;d++){if(a[d].form&&a[d].form.id){do_validate(a[d].form.id,0,0,a[d].id)}}}open_usepass_dialog(e.value)}function init_passtip_dialog(){if(password_tip_panel_initted){return}password_tip_panel_initted=1;password_tip_panel=new YAHOO.widget.Panel("password_tip_panel",{width:"300px",fixedcenter:false,constraintoviewport:false,close:true,draggable:true,modal:false,visible:false});password_tip_panel.setBody(pwminstrength_tip.replace("%",pwminstrength));var a=document.getElementById("sdiv");if(!a){a=document.body}password_tip_panel.render(a);password_tip_panel.hide();document.getElementById("password_tip_panel").style.display=""}function closeUsePass(){password_use_panel.hide()}function init_usepass_dialog(){if(password_use_panel_initted){return}password_use_panel_initted=1;password_use_panel=new YAHOO.widget.Dialog("password_use_panel",{width:"400px",fixedcenter:true,constraintoviewport:true,close:true,draggable:false,modal:false,buttons:[{text:"Close",handler:closeUsePass,isDefault:true}],visible:false});var a=document.getElementById("sdiv");if(!a){a=document.body}password_use_panel.render(a);password_use_panel.hide();document.getElementById("password_use_panel").style.display=""}function init_passgen_dialog(){if(password_gen_panel_initted){return}password_gen_panel_initted=1;password_gen_panel=new YAHOO.widget.Dialog("password_gen_panel",{width:"400px",fixedcenter:true,constraintoviewport:true,close:true,draggable:true,modal:false,buttons:[{text:"Use Password",handler:handlePassSubmit,isDefault:true},{text:"Cancel",handler:handlePassCancel}],visible:false});var a=document.getElementById("sdiv");if(!a){a=document.body}password_gen_panel.render(a);password_gen_panel.hide();document.getElementById("password_gen_panel").style.display=""}function handle_hide_passtip(){if(password_tip_panel.cfg.getProperty("visible")){password_tip_panel.hide()}}function hide_password_tip_panel(){handle_hide_passtip()}function handle_hide_passgen(){}function show_password_tip_panel(){var f=document.getElementById("password");var b=YAHOO.util.Region.getRegion(f);var c=document.getElementById("passwdGen");if(c){var a=YAHOO.util.Region.getRegion(c);if(a.bottom>b.bottom){b.bottom=a.bottom}}password_tip_panel.moveTo(b.right+5,b.bottom+10);if(!password_tip_panel.cfg.getProperty("visible")){password_tip_panel.show();if(f){try{f.focus()}catch(d){}}}}function dialogGeneratePass(){did_password_gen=1;var c=document.getElementById("dialogPassword");var f=document.getElementById("pwlength");var a=parseInt(f.value);if(!a||a<8){a=8}c.setAttribute("size",a);for(var b=0;b<10;b++){c.value=generate_password(a,[document.getElementById("uppercase").checked?"uppercase":"",document.getElementById("lowercase").checked?"lowercase":"",document.getElementById("numbers").checked?"numbers":"",document.getElementById("symbols").checked?"symbols":""],"'oO0\"");var d=c.value+"";var e=getPasswordStrength(d);if(e>=100){break}}updatePasswordStrength_new(c,"Dialog_passwdRating",{text:2,rating:3},1);password_gen_panel.show()}function html_encode_str(a){return a.replace(/\&/g,"&amp;").replace(/\</g,"&lt;").replace(/\>/g,"&gt;").replace(/\"/g,"&quot;")};