package Cpanel::CommuniGate;

use strict;
use vars qw(@ISA @EXPORT $VERSION);
use CLI;
use Cpanel::Logger          ();
use Cpanel::AdminBin ();
use Cpanel::Email ();

use Cpanel                           ();
use Cpanel::SafeDir                  ();
use Cpanel::Rand                     ();
use Cpanel::Encoder::Tiny            ();
use Cpanel::PasswdStrength           ();
use Cpanel::Validate::EmailLocalPart ();
use Cpanel::Validate::EmailRFC       ();
use Cpanel::Sys::Hostname		();
use Cpanel::Api2::Exec ();
use Storable                         ();
use Time::Local  'timelocal_nocheck';
use Digest::MD5 qw(md5_hex);
use XIMSS;
use MIME::QuotedPrint::Perl;
use Cpanel::CSVImport;

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(CommuniGate_init );

$VERSION = '1.0';

my $logger = Cpanel::Logger->new();
my $CLI = undef;
sub CommuniGate_init {
    return 1;
}

sub getCLI {
    if ($CLI && $CLI->{isConnected}) {
	return $CLI;
    } else {
	my $loginData = Cpanel::AdminBin::adminrun('cca', 'GETLOGIN');
	$loginData =~ s/^\.\n//;
	my @loginData = split "::", $loginData;
 	my $cli = new CGP::CLI( { PeerAddr => $loginData[0],
				  PeerPort => $loginData[1],
				  login => $loginData[2],
				  password => $loginData[3]
				});
	unless($cli) {
	    $logger->warn("Can't login to CGPro: ".$CGP::ERR_STRING);
	}
	$CLI = $cli;
	return $cli;
    }
}

sub getXIMSS {
    my ($authData, $password) = @_;
    my $loginData = Cpanel::AdminBin::adminrun('cca', 'GETLOGIN');
    $loginData =~ s/^\.\n//;
    my @loginData = split "::", $loginData;
    my $ximss = new XIMSS({
	PeerAddr => $loginData[0],
	PeerPort => '11024',
	authData => $authData,
	password => $password,
	Proto    => 'tcp'
			  });
    unless($ximss) {
	$logger->warn("Can't connect to CGPro XIMSS: ".$CGP::ERR_STRING);
	exit(0);
    }
    return $ximss;
}

sub max_class_accounts {
 my ($domain, $class) = @_;
 my $data = Cpanel::CachedDataStore::fetch_ref( '/var/cpanel/cgpro/classes.yaml' ) || {};
 if ($data->{$domain}) {
     return $data->{$domain}->{$class}->{all};
 } elsif ($data->{$Cpanel::CPDATA{'PLAN'}}) {
     return $data->{$Cpanel::CPDATA{'PLAN'}}->{$class}->{all};
 } else {
     return $data->{default}->{$class}->{all};
 }
}

sub current_class_accounts {
    my ($class, $cli) = @_;
    my $count = 0;
    my @domains = Cpanel::Email::listmaildomains(); 
    foreach my $domain (@domains) {
	my $accounts = $cli->ListAccounts($domain);
	foreach my $userName (sort keys %$accounts) {      
	    my $accountData = $cli->GetAccountEffectiveSettings("$userName\@$domain");
	    my $service = $accountData->{'ServiceClass'} || '';
	    if ($service eq $class) {
		$count++;
	    }
	}
    }
    return $count;
}

sub api2_AccountsOverview {
	my %OPTS = @_;
	my $invert = $OPTS{'invert'};
	my @domains = Cpanel::Email::listmaildomains(); 
	my $cli = getCLI();
	my @result;
	my $data = Cpanel::CachedDataStore::fetch_ref( '/var/cpanel/cgpro/classes.yaml' ) || {};
	my $return_accounts = {};
	foreach my $domain (@domains) {
	    my $accounts=$cli->ListAccounts($domain);
	    foreach my $userName (sort keys %$accounts) {	
		my $accountData = $cli->GetAccountEffectiveSettings("$userName\@$domain");
		my $accountStats = $cli->GetAccountStat("$userName\@$domain");
		my $service = @$accountData{'ServiceClass'} || '';
		my $accountPrefs = $cli->GetAccountEffectivePrefs("$userName\@$domain");
		my $diskquota = @$accountData{'MaxAccountSize'} || '';
		$diskquota =~ s/M//g;
		my $_diskused = $cli->GetAccountInfo("$userName\@$domain","StorageUsed");
		my $diskused = $_diskused / 1024 /1024;
		my $diskusedpercent;
		if ($diskquota eq "unlimited") {
		    $diskusedpercent = 0;
		} else {
		    $diskusedpercent = $diskused / $diskquota * 100;
		}
		$return_accounts->{$userName . "@" . $domain} = {
		    domain => $domain,
		    username => $userName,
		    class => $service,
		    quota => $diskquota,
		    used => $diskused,
		    data => $accountData,
		    prefs => $accountPrefs,
		    usedpercent => $diskusedpercent,
		    stats => $accountStats,
		    md5 => md5_hex(lc $userName . "@" . $domain),
		};
	    }
	}
	my $defaults = $cli->GetServerAccountDefaults();
	$cli->Logout();
	return { accounts => $return_accounts,
		 classes => $defaults->{'ServiceClasses'},
		 data => $data,
		 sort_keys_by => sub {
		     my $hash = shift;
		     my $sort_field = shift;
		     my $reverse = shift;
		     $sort_field = 'username' if $sort_field !~ /^\w+$/;
		     return sort { $hash->{$b}->{$sort_field} cmp $hash->{$a}->{$sort_field} || $hash->{$b}->{'username'} cmp $hash->{$a}->{'username'} || $hash->{$b}->{'domain'} cmp $hash->{$a}->{'domain'}} keys %$hash if $reverse == 1;
		     return sort { $hash->{$a}->{$sort_field} cmp $hash->{$b}->{$sort_field} || $hash->{$a}->{'username'} cmp $hash->{$b}->{'username'} || $hash->{$a}->{'domain'} cmp $hash->{$b}->{'domain'}} keys %$hash;
		 }
	};
}

sub api2_AccountDefaults {
	my %OPTS = @_;
	my @domains = Cpanel::Email::listmaildomains(); 
	my $cli = getCLI();
	my $domain = $domains[0];
	for my $dom (@domains) {
	    if ($dom eq $OPTS{'domain'}) {
		$domain = $dom;
	    }
	}
	if ($OPTS{'save'}) {
	    my $defaultServerAccountPrefs = $cli->GetServerAccountPrefs();
		$cli->UpdateDomainSettings(
		    domain => $domain,
		    settings => {
			MailRerouteAddress => $OPTS{'MailRerouteAddress'},
			MailToAllAction => $OPTS{'MailToAllAction'},
		    }
		    );
		my $workdays = [map { $OPTS{$_} } grep { /^WorkDays\-?/ }  sort keys %OPTS];
		$cli->UpdateAccountDefaultPrefs(
		    domain => $domain,
		    settings => {
			TimeZone => $OPTS{'TimeZone'},
			WorkDayStart => $OPTS{'WorkDayStart'},
			WorkDayEnd => $OPTS{'WorkDayEnd'},
			WeekStart => $OPTS{'WeekStart'},
			WorkDays => (join(",",@$workdays) eq join(",",@{$defaultServerAccountPrefs->{WorkDays}}) ? 'default' : $workdays),
		    }
		    );
	}
	my $serverDomainDefaults = $cli->GetDomainDefaults();
	my $serverAccountPrefs = $cli->GetServerAccountPrefs();
	my $domainSettings = $cli->GetDomainSettings($domain);
	my $accountDefaultPrefs = $cli->GetAccountDefaultPrefs($domain);
	$cli->Logout();
	return { 
	    serverDomainDefaults => $serverDomainDefaults,
	    serverAccountPrefs => $serverAccountPrefs,
	    domainSettings => $domainSettings,
	    accountDefaultPrefs => $accountDefaultPrefs,
	    domain => $domain
	};
}

sub api2_ListClasses {
	my %OPTS = @_;
	my $invert = $OPTS{'invert'};
	my $cli = getCLI();
	my $defaults = $cli->GetServerAccountDefaults();
	my @return;
	for my $class (sort keys %{$defaults->{'ServiceClasses'}}) {
	    push @return, {class => $class};
	}
	$cli->Logout();
	return @return;
}

sub api2_ListWorkDays {
	my %OPTS = @_;
	my $domain = $OPTS{'domain'};
	my $cli = getCLI();
	my $defaults = $cli->GetServerAccountPrefs();
	if ($domain) {
	    my @domains = Cpanel::Email::listmaildomains(); 
	    for $dom (@domains) {
		if ($dom eq $domain) {
		    $prefs = $cli->GetAccountDefaultPrefs($domain);
		    $defaults->{WorkDays} = $prefs->{WorkDays} if $prefs->{WorkDays};
		    last;
		}
	    }
	}
	$cli->Logout();
	return { default => $defaults->{WorkDays} };
}
sub api2_getDomainAccounts {
	my %OPTS = @_;
	my $domain = $OPTS{'domain'};
	my $cli = getCLI();
	my $accounts = undef;
	if ($domain) {
	    my @domains = Cpanel::Email::listmaildomains(); 
	    for $dom (@domains) {
		if ($dom eq $domain) {
		    $accounts = $cli->ListAccounts($domain);
		    last;
		}
	    }
	}
	$cli->Logout();
	return $accounts;
}

sub api2_UpdateAccountClass {
    my %OPTS = @_;
    my $cli = getCLI();
    my (undef, $domain) = split "@", $OPTS{'account'};
    my $max = max_class_accounts($domain, $OPTS{'class'});
    my $current = 0;
    $current = current_class_accounts($OPTS{'class'}, $cli) if $max > 0;
    if ($max > $current || $max == -1) {
	$cli->UpdateAccountSettings($OPTS{'account'}, { ServiceClass => $OPTS{'class'} });
	$cli->Logout();
	return { msg => "Updated Successfuly." };
    } else {
	$cli->Logout();
	return { msg => "Maximum " .$OPTS{'class'} . " accounts for your plan is $max. Upgrade your plan for more " .$OPTS{'class'} . " accounts." };
    }
}

sub api2_provisioniPhone {
	my %OPTS = @_;
        my $account = $OPTS{'account'};
        my $password = $OPTS{'password'};
        my $number = $OPTS{'number'};
	my @values=split("@",$account);
	my $user=@values[0];
	my $domain=@values[1];
	$number=~ s/\+//; # Remove + from Intl Number
	my $template = "/var/CommuniGate/apple/iphonetemplate.mobileconfig";
	my $random_number = rand();
	$random_number =~ s/0.//;
	my $targetdir="/usr/local/apache/htdocs/iOS";
	# Build the file
	my $cmd="cat ".$template." | sed s/TAGUSER/".$user."/ | sed s/TAGPASS/".$password."/ | sed s/TAGDOMAIN/".$domain."/g > ".$targetdir."/".$random_number.".mobileconfig";
	system("$cmd");

	# Send the SMS
	my $hostname=Cpanel::Sys::gethostname();
	my $mailbody_bulksms="iPhone autoconfig link: $account  http://$hostname/iOS/".$random_number.".mobileconfig";
	open(MAILPIPE, '|/opt/CommuniGate/mail -s 6469646F6F '.$number.'@bulksms.net') or die "Can't open pipe $!";
	print MAILPIPE $mailbody_bulksms;
	close MAILPIPE;
	print "    SMS was sent to $number";
}

sub api2_provisioniPad {
        my %OPTS = @_;
        my $account = $OPTS{'account'};
        my $password = $OPTS{'password'};
        my @values=split("@",$account);
        my $user=@values[0];
        my $domain=@values[1];
        my $template = "/var/CommuniGate/apple/iphonetemplate.mobileconfig";
        my $random_number = rand();
        $random_number =~ s/0.//;
        my $targetdir="/usr/local/apache/htdocs/iOS";
        # Build the file
        my $cmd="cat ".$template." | sed s/TAGUSER/".$user."/ | sed s/TAGPASS/".$password."/ | sed s/TAGDOMAIN/".$domain."/g > ".$targetdir."/".$random_number.".mobileconfig";
        system("$cmd");
	my $hostname=Cpanel::Sys::gethostname();
        my $url ="http://$hostname/iOS/".$random_number.".mobileconfig";
	my @result;
	push (@result, {url => "$url"});
	return @result;
}


sub api2_listpopswithdisk {
        my %OPTS = @_;
	my @domains = Cpanel::Email::listmaildomains();
	my $cli = getCLI;
	my @result;
        foreach my $domain (@domains) {
                my $accounts=$cli->ListAccounts($domain);
                my $userName;
                foreach $userName (sort keys %$accounts) {      
                        my $accountData = $cli->GetAccountEffectiveSettings("$userName\@$domain");
                        my $diskquota = @$accountData{'MaxAccountSize'} || '';
			$diskquota =~ s/M//g;
                        my $_diskquota = $diskquota * 1024 * 1024;
                        my $_diskused = $cli->GetAccountInfo("$userName\@$domain","StorageUsed");
                        my $diskused = $_diskused / 1024 /1024;
			my $diskusedpercent;
			if ($diskquota eq "unlimited") {
				$diskusedpercent = 0;
			} else {
				$diskusedpercent = $_diskused / $diskquota;
			}
			(my $humandiskused) = split('\.',$diskused); $humandiskused .= "M";
			my $humandiskquota = $diskquota."M";
			push( @result, { 	email => "$userName\@$domain", 
						humandiskused => "$humandiskused", 
						humandiskquota => "$humandiskquota", 
						diskusedpercent => "$diskusedpercent", 
						diskused => "$diskused" ,  
						diskquota => "$diskquota", 
						user => "$userName", 
						domain => "$domain", 
						_diskquota => "$_diskquota", 
						_diskused => "$_diskused" } );
		}

	}
	$cli->Logout();
	return @result;
}

sub api2_addforward {
        my %OPTS = @_;
 	my $domain = $OPTS{'domain'};
        my $user = $OPTS{'email'}; 
        my $fwdemail = $OPTS{'fwdemail'};
	my $cli = getCLI();
	my $return =  addforward (
	    domain => $domain,
	    email => $user,
	    fwdemail => $fwdemail,
	    cli => $cli
	    );
	$cli->Logout();
	return $return;
}       

sub addforward {
        my %OPTS = @_;
 	my $domain = $OPTS{'domain'};
        my $user = $OPTS{'email'}; 
        my $fwdemail = $OPTS{'fwdemail'};
        my $cli = $OPTS{'cli'};
	my @result;
	my $account = $cli->GetAccountSettings("$user\@$domain");
	# IF forwarding existing account
	if ($account) {
	    my $Rules=$cli->GetAccountMailRules("$user\@$domain");
	    my $error_msg = $cli->getErrMessage();
	    if (!($error_msg eq "OK")) {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
	    } else {
		my $found=0;
		my @NewRules;
		foreach my $Rule (@$Rules) {
		    if ($Rule->[1] eq "#Redirect") {
			my %rules;
			for my $mail (split(',', $Rule->[3]->[0]->[1])) {
			    $rules{$mail} = 1;
			}
			$rules{$fwdemail} = 1;
			$Rule->[3]->[0]->[1] = join(',', keys(%rules));
			$found=1;
		    }       
		    push(@NewRules,$Rule);
		}
		if (!$found) {
		    my $Rule= [1,'#Redirect',[],[['Mirror to',$fwdemail]]];
		    push(@NewRules,$Rule);
		}		
		$cli->SetAccountMailRules("$user\@$domain",\@NewRules);
		$error_msg = $cli->getErrMessage();
		if ($error_msg eq "OK") {
		    push( @result, { email => "$user\@$domain", forward => "$fwdemail", domain => "$domain" } );
		} else {
		    $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
		}
	    }
	#  IF forwarding nonexisting account
	} else {
	    # IF forwarding TO local account
	    if ($cli->GetAccountSettings("$fwdemail")) {
		my $aliases = $cli->GetAccountAliases("$fwdemail");
		my $found = 0;
		for my $alias (@$aliases) {
		    $found = 1 if "$alias" eq "$user";
		}
		push @$aliases, "$user" unless $found;
		my $aliases = $cli->SetAccountAliases($fwdemail, $aliases);
		my $error_msg = $cli->getErrMessage();
		if ($error_msg eq "OK") {
		    push( @result, { email => "$user\@$domain", forward => "$fwdemail", domain => "$domain" } );
		} else {
		    $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
		}
            # IF forwarding to NON local acount
	    } else {
		$cli->CreateForwarder("$user\@$domain", "$fwdemail");
		my $error_msg = $cli->getErrMessage();
		if ($error_msg eq "OK") {
		    push( @result, { email => "$user\@$domain", forward => "$fwdemail", domain => "$domain" } );
		} else {
		    $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
		}
	    }
	}
        return @result;

}

sub api2_listforwards {
  my %OPTS = @_;
  my $specified_domain  = $OPTS{'domain'};
  my @domains = Cpanel::Email::listmaildomains($OPTS{'domain'});
  my $cli = getCLI();
  my @result;
  foreach my $domain (@domains) {
    if (($specified_domain eq "") || ($specified_domain eq $domain)) {
      my $accounts=$cli->ListAccounts($domain);
      foreach my $userName (sort keys %$accounts) {
	my $Rules=$cli->GetAccountMailRules("$userName\@$domain") || die "Error: ".$cli->getErrMessage.", quitting";
	foreach my $Rule (@$Rules) {
	  if ($Rule->[1] eq "#Redirect") {
	    my @dest = split(",",$Rule->[3]->[0]->[1]);
	    foreach my $value (@dest) {
	      push( @result, {       uri_dest => "$userName%40$domain",
				     html_dest => "$userName\@$domain",
				     dest => "$userName\@$domain",
				     uri_forward => "$value",
				     html_forward => "$value" ,
				     forward => "$value" } );
	    }
	  }
	}
	my $aliases = $cli->GetAccountAliases("$userName\@$domain");
	for my $alias (@$aliases) {
	  push( @result, { uri_dest => "$alias%40$domain",
			   html_dest => "$alias\@$domain",
			   dest => "$alias\@$domain",
			   uri_forward => "$useName%40$domain",
			   html_forward => "$userName\@$domain" ,
			   forward => "$userName\@$domain" } );
	}
      }
      my $forwarders = $cli->ListForwarders($domain);
      foreach my $forwarder (@$forwarders) {
	my $fwd = $cli->GetForwarder("$forwarder\@$domain");
	push( @result, { uri_dest => "$forwarder%40$domain",
			 html_dest => "$forwarder\@$domain",
			 dest => "$forwarder\@$domain",
			 uri_forward => "$fwd",
			 html_forward => "$fwd" ,
			 forward => "$fwd" } );

      }
    }
  }
  $cli->Logout();
  return @result;
}



sub api2_delforward {
        my %OPTS = @_;
        my $domain = $OPTS{'domain'};
        my $user = $OPTS{'account'};
        my $fwdemail = $OPTS{'forwarder'};
	my $cli = getCLI();
        my @result;
	my $account = $cli->GetAccountSettings("$user");
	# IF forwarding existing account
	if ($account) {
	  my $Rules = $cli->GetAccountMailRules("$user") || die "Error: ".$cli->getErrMessage.", quitting";
	  foreach my $Rule (@$Rules) {
	    if ($Rule->[1] eq "#Redirect") {
	      my @dest = split(",",$Rule->[3]->[0]->[1]);
	      $Rule->[3]->[0]->[1] ="";
	      my $found=0;
	      foreach my $value (@dest) {
		if ((!($value eq $fwdemail)) || $found) {
		  if ($Rule->[3]->[0]->[1]) {
		    $Rule->[3]->[0]->[1]  .=	",".$value;
		  } else {
		    $Rule->[3]->[0]->[1]  =     $value;
		  }	
		} else {
		  $found = 1;	
		} 
	      }
	    }
	  }
	  $cli->SetAccountMailRules("$user",$Rules);
	  my $error_msg = $cli->getErrMessage();
	  if ($error_msg eq "OK") {
	    push( @result, { email => "$user", forward => "$fwdemail"} );
	  } else {
	    $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
	  }
	} else {
	  # IF forwarding TO local account
	  if ($cli->GetAccountSettings("$fwdemail")) {
	    my $aliases = $cli->GetAccountAliases("$fwdemail");
	    my $newaliases = [];
	    my ($thealias, undef) = split "@", $user;
	    for my $alias (@$aliases) {
	      push @$newaliases, $alias unless $alias eq $thealias;
	    }
	    $cli->SetAccountAliases("$fwdemail", $newaliases);
	    my $error_msg = $cli->getErrMessage();
	    if ($error_msg eq "OK") {
	      push( @result, { email => "$user", forward => "$fwdemail"} );
	    } else {
	      $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
	    }
            # IF forwarding to NON local acount
	  } else {
	    $cli->DeleteForwarder("$user");
	    my $error_msg = $cli->getErrMessage();
	    if ($error_msg eq "OK") {
	      push( @result, { email => "$user", forward => "$fwdemail" } );
	    } else {
	      $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
	    }
	  }
	}
	$cli->Logout();
        return @result;
}


sub api2_ListDefAddress {
        my %OPTS = @_;
	my $cli = getCLI();
	my @result;
	my @domains = Cpanel::Email::listmaildomains();
	foreach my $domain (@domains) {
		my $domaindata = $cli->GetDomainEffectiveSettings("$domain");
                my $action = @$domaindata{'MailToUnknown'} || '';
		my $forwardaddress = @$domaindata{'MailRerouteAddress'} || '';
		my $entry = { domain => "$domain",reject => "",discard =>"",forward=>"",acceptedandbounced =>"" };
		if ($action eq "Rejected") { $entry->{'reject'} = "selected"; }
		if ($action eq "Discarded") { $entry->{'discard'} = "selected"; }
		if ($action eq "Rerouted to") { $entry->{'forward'} = "selected"; }
		if ($action eq "Accepted and Bounced") { $entry-> {'acceptedandbounced'} = "selected"; }
		push( @result, $entry );
	}	
        $cli->Logout();
        return @result;
}

sub api2_SetDefAddress {
        my %OPTS = @_;
	my $domain = $OPTS{'domain'};
	my $action = $OPTS{'action'};
	my $fwdmail= $OPTS{'fwdmail'};
	my $cli = getCLI();
	my $data = $cli->GetDomainSettings("$domain");
	$cli->CreateDomain("$domain") unless $data;
	my $domainData;
	if ($action eq "CGPDefDiscard") { @$domainData{'MailToUnknown'} = "Discarded"; }
	if ($action eq "CGPDefReject") { @$domainData{'MailToUnknown'} = "Rejected"; }
	if ($action eq "CGPDefForward") { @$domainData{'MailToUnknown'} = "Rerouted to"; @$domainData{'MailRerouteAddress'} = "$fwdmail"; }
	if ($action eq "CGPDefAcceptedAndBounced") { @$domainData{'MailToUnknown'} = "Accepted and Bounced"; }
        $cli->UpdateDomainSettings(domain => $domain,settings => $domainData);
        $cli->Logout();
}

sub api2_SpamAssassinStatus {
	my %OPTS = @_;
        my $account_domain  = $OPTS{'domain'};
	my $sa_rulname = "scanspam-".$account_domain;
	my $cli = getCLI();
	my $Rules=$cli->GetServerRules() || die "Error: ".$cli->getErrMessage.", quitting";
	my @result;
   	foreach my $Rule (@$Rules) {
		if ($Rule->[1] eq "$sa_rulname") {
			push( @result, { status => "enabled" } );
        		$cli->Logout();
        		return @result;
		}
        }
        push( @result, { status => "disabled" } );
	$cli->Logout();
        return @result;
}

sub api2_EnableSpamAssassin {
        my %OPTS = @_;
        my $account_domain  = $OPTS{'domain'};
        my $sa_rulname = "scanspam-".$account_domain;
	my $account = $Cpanel::authuser;
	my $cli = getCLI();
        my @result;
	my $ExistingRules=$cli->GetServerRules() || die "Error: ".$cli->getErrMessage.", quitting";
	my @domains = Cpanel::Email::listmaildomains();
	my @NewRules;
        foreach my $domain (@domains) {
	 my $sa_rulname = "scanspam-".$domain;
 	 my $NewRule =
  		[ 5, $sa_rulname ,
    			[ 
				['Any Recipient', 'in', '*@'.$domain],
				['Header Field', 'is not', 'X-Spam-Status*'] 
			],
    			[ 
				['Execute', '[STDERR] [FILE] [RETPATH] [RCPT] /var/CommuniGate/spamassassin/scanspam.sh '.$account], 
				['Discard']
			]
  		];
	 push(@NewRules,$NewRule);
         push( @result, { status => "domain: $domain ...done\n" } );
	}
	foreach my $Rule (@$ExistingRules) {
		push(@NewRules,$Rule);
        }      	

  	$cli->SetServerRules(\@NewRules) || die "Error: ".$cli->getErrMessage.", quitting";
        $cli->Logout();
        return @result;
}

sub api2_DisableSpamAssassin {
        my %OPTS = @_;
        my $account_domain  = $OPTS{'domain'};
	my $cli = getCLI();
        my $Rules=$cli->GetServerRules() || die "Error: ".$cli->getErrMessage.", quitting";
        my @result;
	my @NewRules;
 	my @domains = Cpanel::Email::listmaildomains();
        foreach my $Rule (@$Rules) {
	 my $match=0;
         foreach my $domain (@domains) {
	        my $sa_rulname = "scanspam-".$domain;
                if ($Rule->[1] eq "$sa_rulname") {
			push( @result, { status => "domain: $domain ...done\n" } );
			$match=1;
                }
	 }
         if (!$match) {push( @NewRules, $Rule );}
        }
	$cli->SetServerRules(\@NewRules) || die "Error: ".$cli->getErrMessage.", quitting";
        $cli->Logout();
        return @result;
}

sub count_x {
 my $string = shift;
 my $count = 0;
 while ($string =~ /x/g) { $count++ }
 return $count;
}


sub api2_SpamAssassinStatusAutoDelete {
	my %OPTS = @_;
        my $account_domain  = $OPTS{'domain'};
	my $sa_rulname = "deletespam-".$account_domain;
	my $cli = getCLI();
 	my $Rules=$cli->GetServerRules() || die "Error: ".$cli->getErrMessage.", quitting";
	my @result;
   	foreach my $Rule (@$Rules) {
		if ($Rule->[1] eq "$sa_rulname") {
			push( @result, { status => "enabled" } );
			$Cpanel::CPVAR{'spam_auto_delete'} = 1;
			$Cpanel::CPVAR{'spam_auto_delete_score'} = count_x($Rule->[2]->[0]->[2]);
        		$cli->Logout();
        		return @result;
		}
        }
        push( @result, { status => "disabled" } );
	$Cpanel::CPVAR{'spam_auto_delete'} = 0;
	$cli->Logout();
        return @result;
}

sub api2_EnableSpamAssassinAutoDelete {
        my %OPTS = @_;
        my $account_domain  = $OPTS{'domain'};
        my $score = $OPTS{'score'};
	my $score_string = "";
	for (my $i=0;$i<$score;$i++) {$score_string .= "x"; }
        my $sa_rulname = "deletespam-".$account_domain;
	my $cli = getCLI();
        my @result;
	my $ExistingRules=$cli->GetServerRules() || die "Error: ".$cli->getErrMessage.", quitting";
	my @domains = Cpanel::Email::listmaildomains();
	my @NewRules;
        foreach my $domain (@domains) {
	 my $sa_rulname = "deletespam-".$domain;
 	 my $NewRule =
  		[ 4, $sa_rulname ,
    			[ 
				['Header Field', 'is', 'X-Spam-Level: '.$score_string.'*'] 
			],
    			[ 
				['Discard']
			]
  		];
	 push(@NewRules,$NewRule);
         push( @result, { status => "domain: $domain ...done\n" } );
	}
	foreach my $Rule (@$ExistingRules) {
		push(@NewRules,$Rule);
        }      	

  	$cli->SetServerRules(\@NewRules) || die "Error: ".$cli->getErrMessage.", quitting";
        $cli->Logout();
        return @result;
}

sub api2_DisableSpamAssassinAutoDelete {
        my %OPTS = @_;
        my $account_domain  = $OPTS{'domain'};
	my $cli = getCLI();
        my $Rules=$cli->GetServerRules() || die "Error: ".$cli->getErrMessage.", quitting";
        my @result;
	my @NewRules;
 	my @domains = Cpanel::Email::listmaildomains();
        foreach my $Rule (@$Rules) {
	 my $match=0;
         foreach my $domain (@domains) {
	        my $sa_rulname = "deletespam-".$domain;
                if ($Rule->[1] eq "$sa_rulname") {
			push( @result, { status => "domain: $domain ...done\n" } );
			$match=1;
                }
	 }
         if (!$match) {push( @NewRules, $Rule );}
        }
	$cli->SetServerRules(\@NewRules) || die "Error: ".$cli->getErrMessage.", quitting";
        $cli->Logout();
        return @result;
}

sub api2_SpamAssassinStatusSpamBox {
	my %OPTS = @_;
        my $account_domain  = $OPTS{'domain'};
	my $sa_rulname = "spambox";
	my $cli = getCLI();
	my $Rules=$cli->GetDomainMailRules($account_domain) || die "Error: ".$cli->getErrMessage.", quitting";
	my @result;
   	foreach my $Rule (@$Rules) {
		if ($Rule->[1] eq "$sa_rulname") {
			push( @result, { status => "enabled" } );
        		$cli->Logout();
        		return @result;
		}
        }
        push( @result, { status => "disabled" } );
	$cli->Logout();
        return @result;
}

sub api2_EnableSpamAssassinSpamBox {
        my %OPTS = @_;
        my $account_domain  = $OPTS{'domain'};
        my $score = $OPTS{'score'};
	my $score_string = "";
	for (my $i=0;$i<$score;$i++) {$score_string .= "x"; }
        my $sa_rulname = "spambox";
	my $cli = getCLI();
        my @result;
	my @domains = Cpanel::Email::listmaildomains();
	my @NewRules;
        foreach my $domain (@domains) {
         @NewRules=();
	 my $ExistingRules=$cli->GetDomainMailRules($domain) || die "Error: ".$cli->getErrMessage.", quitting";
	 my $sa_rulname = "spambox";
 	 my $NewRule =
  		[ 4, $sa_rulname ,
    			[ 
				['Header Field', 'is', 'X-Spam-Flag: YES'] 
			],
    			[
				['Store in', 'Spam'], 
				['Discard']
			]
  		];
	 push(@NewRules,$NewRule);
         push( @result, { status => "domain: $domain ...done\n" } );
	 foreach my $Rule (@$ExistingRules) {
	 	push(@NewRules,$Rule);
         }      	
	 $cli->SetDomainMailRules($domain,\@NewRules) || die "Error: ".$cli->getErrMessage.", quitting";		
        }
        $cli->Logout();
        return @result;
}

sub api2_DisableSpamAssassinSpamBox {
        my %OPTS = @_;
        my $account_domain  = $OPTS{'domain'};
	my $cli = getCLI();
        my @result;
	my @NewRules;
 	my @domains = Cpanel::Email::listmaildomains();
        foreach my $domain (@domains) {
	 @NewRules=();
	 my $Rules=$cli->GetDomainMailRules($domain) || die "Error: ".$cli->getErrMessage.", quitting";
         foreach my $Rule (@$Rules) {
	  my $sa_rulname = "spambox";
          if ($Rule->[1] eq "$sa_rulname") {
	   push( @result, { status => "domain: $domain ...done\n" } );
          } else {
	   push( @NewRules, $Rule );
          }
	 }
	 $cli->SetDomainMailRules($domain,\@NewRules) || die "Error: ".$cli->getErrMessage.", quitting";
        }
        $cli->Logout();
        return @result;
}

sub AddCGPAccount {
	my ( $email, $password, $quota ) = @_;
	my @values = split('@',$email);
	my $user=@values[0];
	my $domain=@values[1];
	my $cli = getCLI();

	if ($quota == 0) {
        	$quota="unlimited" ;
	}else{
        	$quota .= "M";
	}

	my $data=$cli->GetDomainSettings("$domain");

	if (!$data) {
        	$cli->CreateDomain("$domain");
	}
	my $UserData;
	@$UserData{'Password'}=$password;
	@$UserData{'ServiceClass'}="mailonly";
	@$UserData{'MaxAccountSize'}=$quota;

	$cli->CreateAccount(accountName => "$user\@$domain", settings => $UserData);

	my $error_msg = $cli->getErrMessage();
	my $result;
        if ($error_msg eq "OK") {
		$result = 1;
        } else {
		$result=0;
        }

	$cli->CreateMailbox("$user\@$domain", "Calendar");
	$cli->CreateMailbox("$user\@$domain", "Spam");
	$cli->Logout();
	return $result;
}


sub CommuniGate_doimport {
    my ( $id, $type, $domain ) = @_;
    return if ( !Cpanel::hasfeature('csvimport') );
    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        print 'Sorry, this feature is disabled in demo mode.';
        return;
    }

    if ( !$domain ) {
        $domain = $Cpanel::CPDATA{'DNS'};
    }

    $id =~ s/\///g;

    my $file       = $Cpanel::homedir . '/tmp/cpcsvimport/' . $id;
    my $importdata = Storable::lock_retrieve( $file . '.import' );

    my $numrows  = scalar @$importdata;
    my $rowcount = 0;
    foreach my $row (@$importdata) {
        $rowcount++;
        my ( $status, $msg );
        if ( $type eq 'fwd' ) {
            ( $status, $msg ) = Cpanel::Email::addforward( $row->{'source'}, $row->{'target'}, $domain, 1 );
            print '<div class="statusline"><div class="statusitem">' . Cpanel::Encoder::Tiny::safe_html_encode_str("$row->{'source'} => $row->{'target'} ") . '</div><div class="status ' . ( $status ? 'green-status' : 'red-status' ) . '">' . $msg . '</div></div>' . "\n";
        }
        else {
            ( $status, $msg ) = Cpanel::Email::addpop( $row->{'email'}, $row->{'password'}, $row->{'quota'}, '', 0, 1 );
	    if ($status) { $status = AddCGPAccount($row->{'email'}, $row->{'password'}, $row->{'quota'})}; 
            print '<div class="statusline"><div class="statusitem">' . Cpanel::Encoder::Tiny::safe_html_encode_str( $row->{'email'} ) . '</div><div class="status ' . ( $status ? 'green-status' : 'red-status' ) . '">' . $msg . '</div></div>' . "\n";
        }
        print qq{<script>setcompletestatus($rowcount,$numrows)</script>\n\n};
    }

}

sub api2_AddMailingList {
        my %OPTS = @_;
        my $domain = $OPTS{'domain'};
        my $listname = $OPTS{'email'};
        my $owner = $OPTS{'owner'};
	my $cli = getCLI();
        $cli->CreateList("$listname\@$domain","$owner");
        my $error_msg = $cli->getErrMessage();
        my @result;
        if ($error_msg eq "OK") {
                push( @result, { email => "$listname", domain => "$domain" } );
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }
	$cli->Logout();
        return @result;
}

sub api2_ListMailingLists {
        my %OPTS = @_;
	@domains = Cpanel::Email::listmaildomains();
	my $cli = getCLI();
        my @result;
	foreach my $domain (@domains) {
		my $lists=$cli->GetDomainLists($domain);
                foreach $listName (sort keys %$lists) {
		 push( @result, { list => "$listName\@$domain" , domain =>"$domain"} );
		}
	}
	$cli->Logout();
        return @result;
}



sub api2_DelMailingList {
        my %OPTS = @_;
        my $listname = $OPTS{'email'};
	my $cli = getCLI();
        $cli->DeleteList("$listname");
        my $error_msg = $cli->getErrMessage();
        my @result;
        if ($error_msg eq "OK") {
                push( @result, { email => "$listname" } );
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }       
	$cli->Logout();
        return @result;
}

sub api2_RenameMailingList {
        my %OPTS = @_;
        my $email = $OPTS{'email'};
        my $newname = $OPTS{'newname'};
	my $cli = getCLI();
        $cli->RenameList("$email","$newname");
        my $error_msg = $cli->getErrMessage();
        my @result;
        if ($error_msg eq "OK") {
                push( @result, { email => "$email" } );
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }
	$cli->Logout();
        return @result;
}


# Mailing List Global Variables for Settings Page

my @IndexesToValues_OwnerCheck;
my %ValuesToIndexes_OwnerCheck;
my @IndexesToValues_Charset;
my %ValuesToIndexes_Charset;
my %ValuesToIndexes_Subscribe;
my @IndexesToValues_Subscribe;
my %ValuesToIndexes_SaveRequests;
my @IndexesToValues_SaveRequests;
my %ValuesToIndexes_Distribution;
my @IndexesToValues_Distribution;

sub MLSettingsSetIndexToValue {
	@IndexesToValues_OwnerCheck = ( "Return-Path", "IP Addresses", "Authentication" );
	@IndexesToValues_Charset = ("iso-8859-1","windows-1252","iso-2022-jp","euc-jp","shift-jis","koi8-r","iso-8859-5","windows-1251","cp866","koi8-u","iso-8859-2","windows-1250","iso-8859-7","windows-1253","iso-8859-8","windows-1255","iso-8859-9","windows-1254","iso-8859-4","windows-1257","big5","gb2312","gb18030","gbk","euc-tw","iso-2022-kr","euc-kr","ks_c_5601-1987","iso-8859-6","windows-1256","iso-8859-11","windows-874","iso-8859-3","iso-8859-10","iso-8859-13","iso-8859-14","iso-8859-15","iso-8859-16","windows-1258","utf-8");
	@IndexesToValues_Subscribe = ("nobody","moderated","this domain only","locals only","anybody");
	@IndexesToValues_SaveRequests= ("no","accepted","rejected","all");
	@IndexesToValues_Distribution = ("feed","null","banned","digest","index");
	@IndexesToValues_Postings = ("from owner only","moderated","from subscribers","moderate guests","from anybody"); 
	@IndexesToValues_Format = ("plain text only","text only","text alternative","anything");
	@IndexesToValues_SizeLimit = ("unlimited","0","1024","3K","10K","30K","100K","300K","1024K","3M","10M","300M");
	@IndexesToValues_CoolOffPeriod= ("1h","2h","3h","6h","12h","1d","2d","3d","5d","7d","10d");
	@IndexesToValues_UnsubBouncedPeriod= ("1h","2h","3h","6h","12h","1d","2d","3d","5d","7d","10d");
	@IndexesToValues_CleanupPeriod= ("1h","2h","3h","6h","12h","1d","2d","3d","5d","7d","10d");
	@IndexesToValues_SaveReports=("no","unprocessed","all");
	@IndexesToValues_Reply=("to list","to sender");
	@IndexesToValues_ArchiveSizeLimit=("unlimited","0","1024","3K","10K","30K","100K","300K","1024K","3M","10M","30M","100M","300M","1024M","3G","10G","30G");
}

sub MLSettingsSetValueToIndex {
        %ValuesToIndexes_OwnerCheck = ( "Return-Path",0,"IP Addresses",1,"Authentication",2 );
	%ValuesToIndexes_Charset = ( "iso-8859-1",0,"windows-1252",1,"iso-2022-jp",2,"euc-jp",3,"shift-jis",4,"koi8-r",5,"iso-8859-5",6,"windows-1251",7,"cp866",8,"koi8-u",9,"iso-8859-2",10,"windows-1250",11,"iso-8859-7",12,"windows-1253",13,"iso-8859-8",14,"windows-1255",15,"iso-8859-9",16,"windows-1254",17,"iso-8859-4",18,"windows-1257",19,"big5",20,"gb2312",21,"gb18030",22,"gbk",23,"euc-tw",24,"iso-2022-kr",25,"euc-kr",26,"ks_c_5601-1987",27,"iso-8859-6",28,"windows-1256",29,"iso-8859-11",30,"windows-874",31,"iso-8859-3",32,"iso-8859-10",33,"iso-8859-13",34,"iso-8859-14",35,"iso-8859-15",36,"iso-8859-16",37,"windows-1258",38,"utf-8",39);
	%ValuesToIndexes_Subscribe= ("nobody",0,"moderated",1,"this domain only",2,"locals only",3,"anybody",4);
	%ValuesToIndexes_SaveRequests= ("no",0,"accepted",1,"rejected",2,"all",3);
	%ValuesToIndexes_Distribution = ("feed",0,"null",1,"banned",2,"digest",3,"index",4);
	%ValuesToIndexes_Postings = ("from owner only",0,"moderated",1,"from subscribers",2,"moderate guests",3,"from anybody",4); 
	%ValuesToIndexes_Format = ("plain text only",0,"text only",1,"text alternative",2,"anything",3);
	%ValuesToIndexes_SizeLimit = ("unlimited",0,"0",1,"1024",2,"3K",3,"10K",4,"30K",5,"100K",6,"300K",7,"1024K",8,"3M",9,"10M",10,"300M",11);
	%ValuesToIndexes_CoolOffPeriod = ("1h",0,"2h",1,"3h",2,"6h",3,"12h",4,"1d",5,"2d",6,"3d",7,"5d",8,"7d",9,"10d",10);
	%ValuesToIndexes_UnsubBouncedPeriod= ("1h",0,"2h",1,"3h",2,"6h",3,"12h",4,"1d",5,"2d",6,"3d",7,"5d",8,"7d",9,"10d",10);
	%ValuesToIndexes_CleanupPeriod= ("1h",0,"2h",1,"3h",2,"6h",3,"12h",4,"1d",5,"2d",6,"3d",7,"5d",8,"7d",9,"10d",10);
	%ValuesToIndexes_SaveReports=("no",0,"unprocessed",1,"all",2);
	%ValuesToIndexes_Reply=("to list",0,"to sender",1);
	%ValuesToIndexes_ArchiveSizeLimit=("unlimited",0,"0",1,"1024",2,"3K",3,"10K",4,"30K",5,"100K",6,"300K",7,"1024K",8,"3M",9,"10M",10,"30M",11,"100M",12,"300M",13,"1024M",14,"3G",15,"10G",16,"30G",17);

	
}


sub api2_GetListSettings {

	# Select values : 
	MLSettingsSetValueToIndex();

        my %OPTS = @_;
        my $email = $OPTS{'email'};
	my $cli = getCLI();
        my $listSettings = $cli->GetList("$email");
        my $error_msg = $cli->getErrMessage();
        my @result;
        if ($error_msg eq "OK") {
		foreach (keys %$listSettings) {
			my $key=$_;
			my $value = @$listSettings{$key};
                	push( @result, { "$key" => "$value" } );
			if ($key eq "OwnerCheck") { 
				$Cpanel::CPDATA{"$key"} = $ValuesToIndexes_OwnerCheck{$value};
			} elsif ($key eq "Charset") {
				$Cpanel::CPDATA{"$key"} = $ValuesToIndexes_Charset{$value};
                        } elsif ($key eq "Subscribe") {
                                $Cpanel::CPDATA{"$key"} = $ValuesToIndexes_Subscribe{$value};
                        } elsif ($key eq "SaveRequests") {
                                $Cpanel::CPDATA{"$key"} = $ValuesToIndexes_SaveRequests{$value};
                        } elsif ($key eq "Distribution") {
                                $Cpanel::CPDATA{"$key"} = $ValuesToIndexes_Distribution{$value};
                        } elsif ($key eq "Postings") {
                                $Cpanel::CPDATA{"$key"} = $ValuesToIndexes_Postings{$value};
                        } elsif ($key eq "Format") {
                                $Cpanel::CPDATA{"$key"} = $ValuesToIndexes_Format{$value};
                       } elsif ($key eq "SizeLimit") {
                                $Cpanel::CPDATA{"$key"} = $ValuesToIndexes_SizeLimit{$value};
                       } elsif ($key eq "CoolOffPeriod") {
                                $Cpanel::CPDATA{"$key"} = $ValuesToIndexes_CoolOffPeriod{$value};
                       } elsif ($key eq "UnsubBouncedPeriod") {
                                $Cpanel::CPDATA{"$key"} = $ValuesToIndexes_UnsubBouncedPeriod{$value};
                       } elsif ($key eq "CleanupPeriod") {
                                $Cpanel::CPDATA{"$key"} = $ValuesToIndexes_CleanupPeriod{$value};
                       } elsif ($key eq "SaveReports") {
                                $Cpanel::CPDATA{"$key"} = $ValuesToIndexes_SaveReports{$value};
                       } elsif ($key eq "Reply") {
                                $Cpanel::CPDATA{"$key"} = $ValuesToIndexes_Reply{$value};
                      } elsif ($key eq "ArchiveSizeLimit") {
                                $Cpanel::CPDATA{"$key"} = $ValuesToIndexes_ArchiveSizeLimit{$value};
                     } elsif ($key eq "DigestFormat") {
                                $Cpanel::CPDATA{"$key"} = $value;
				$Cpanel::CPDATA{"$key"} =~ s/ /_/g;
			} else {
				$Cpanel::CPDATA{"$key"} = "$value";
			}
  		}
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }
	$cli->Logout();
        return @result;
}

#Used to set values
sub html_to_text {
 my $text=shift;
 $text =~ s/\r//g;
 $text =~ s/&quot;/\\\"/g;
 $text =~ s/&lt;/</g;
 $text =~ s/&gt;/>/g;
 $text =~ s/&amp;/\&/g; 
 return($text);
}

sub html_to_text_out {
 my $text=shift;
 $text =~ s/\r//g;
 $text =~ s/&quot;/\"/g;
 $text =~ s/&lt;/</g;
 $text =~ s/&gt;/>/g;
 $text =~ s/&amp;/\&/g;
 return($text);
}


sub api2_SetListSettings {

      # Select values : 
        MLSettingsSetIndexToValue();

        my %OPTS = @_;
        my $email = $OPTS{'email'};
	my $cli = getCLI();
        my $listSettings;
	@$listSettings{'Charset'} = @IndexesToValues_Charset[$OPTS{'Charset'}];
	@$listSettings{'OwnerCheck'} = @IndexesToValues_OwnerCheck[$OPTS{'OwnerCheck'}];
	@$listSettings{'Subscribe'} = @IndexesToValues_Subscribe[$OPTS{'Subscribe'}];
	@$listSettings{'SaveRequests'} = @IndexesToValues_SaveRequests[$OPTS{'SaveRequests'}];
	@$listSettings{'Distribution'} = @IndexesToValues_Distribution[$OPTS{'Distribution'}];
	@$listSettings{'Confirmation'} = ($OPTS{'Confirmation'}?'YES':'NO');
	@$listSettings{'ConfirmationSubject'} = html_to_text($OPTS{'ConfirmationSubject'});
	@$listSettings{'ConfirmationText'} = html_to_text($OPTS{'ConfirmationText'});
	@$listSettings{'Postings'} = @IndexesToValues_Postings[$OPTS{'Postings'}];
	@$listSettings{'FirstModerated'} = $OPTS{'FirstModerated'};
	@$listSettings{'Format'} = @IndexesToValues_Format[$OPTS{'Format'}];
	@$listSettings{'SizeLimit'} = @IndexesToValues_SizeLimit[$OPTS{'SizeLimit'}];
	@$listSettings{'CheckDigestSubject'} = ($OPTS{'CheckDigestSubject'}?'YES':'NO');
	@$listSettings{'CheckCharset'} = ($OPTS{'CheckCharset'}?'YES':'NO');
	@$listSettings{'ListFields'} = html_to_text($OPTS{'ListFields'});
	@$listSettings{'HideFromAddress'} = ($OPTS{'HideFromAddress'}?'YES':'NO');
	@$listSettings{'TillConfirmed'} = ($OPTS{'TillConfirmed'}?'YES':'NO');
	@$listSettings{'CoolOffPeriod'} = @IndexesToValues_CoolOffPeriod[$OPTS{'CoolOffPeriod'}];
	@$listSettings{'MaxBounces'} = $OPTS{'MaxBounces'};
	@$listSettings{'UnsubBouncedPeriod'} = @IndexesToValues_UnsubBouncedPeriod[$OPTS{'UnsubBouncedPeriod'}];
	@$listSettings{'FatalWeight'} = $OPTS{'FatalWeight'};
	@$listSettings{'FailureNotification'} = ($OPTS{'FailureNotification'}?'YES':'NO');
	@$listSettings{'CleanupPeriod'} = @IndexesToValues_CleanupPeriod[$OPTS{'CleanupPeriod'}];
	@$listSettings{'SaveReports'} = @IndexesToValues_SaveReports[$OPTS{'SaveReports'}];
        @$listSettings{'WarningSubject'} = html_to_text($OPTS{'WarningSubject'});
        @$listSettings{'WarningText'} = html_to_text($OPTS{'WarningText'});
        @$listSettings{'FeedSubject'} = html_to_text($OPTS{'FeedSubject'});
	@$listSettings{'Reply'} = @IndexesToValues_Reply[$OPTS{'Reply'}];
	@$listSettings{'FeedPrefixMode'} = ($OPTS{'FeedPrefixMode'}?'YES':'NO');
        @$listSettings{'FeedHeader'} = html_to_text($OPTS{'FeedHeader'});
        @$listSettings{'FeedTrailer'} = html_to_text($OPTS{'FeedTrailer'});
        @$listSettings{'PolicySubject'} = html_to_text($OPTS{'PolicySubject'});
        @$listSettings{'PolicyText'} = html_to_text($OPTS{'PolicyText'});
        @$listSettings{'ByeSubject'} = html_to_text($OPTS{'ByeSubject'});
        @$listSettings{'ByeText'} = html_to_text($OPTS{'ByeText'});
	@$listSettings{'Store'} = ($OPTS{'Store'}?'YES':'NO');
	@$listSettings{'ArchiveSizeLimit'} = @IndexesToValues_ArchiveSizeLimit[$OPTS{'ArchiveSizeLimit'}];
	@$listSettings{'ArchiveMessageLimit'} = $OPTS{'ArchiveMessageLimit'};
	@$listSettings{'ArchiveSwapPeriod'} = $OPTS{'ArchiveSwapPeriod'};
	@$listSettings{'Browse'} = $OPTS{'Browse'};
	@$listSettings{'DigestPeriod'} = $OPTS{'DigestPeriod'};
	@$listSettings{'DigestSizeLimit'} = $OPTS{'DigestSizeLimit'};
	@$listSettings{'DigestMessageLimit'} = $OPTS{'DigestMessageLimit'};
	@$listSettings{'DigestTimeOfDay'} = $OPTS{'DigestTimeOfDay'};
        @$listSettings{'DigestSubject'} = html_to_text($OPTS{'DigestSubject'});
	@$listSettings{'DigestFormat'} = $OPTS{'DigestFormat'};
        @$listSettings{'DigestHeader'} = html_to_text($OPTS{'DigestHeader'});
        @$listSettings{'TOCLine'} = html_to_text($OPTS{'TOCLine'});
        @$listSettings{'TOCTrailer'} = html_to_text($OPTS{'TOCTrailer'});
        @$listSettings{'DigestTrailer'} = html_to_text($OPTS{'DigestTrailer'});

	$cli->UpdateList("$email",$listSettings);
        my $error_msg = $cli->getErrMessage();
        my @result;
        if ($error_msg eq "OK") {
		#noop
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }
	$cli->Logout();
        return @result;
}


sub CommuniGate_PrintTextArea_api1 {
 my ($text) = @_;
 @lines = split(/\\e/,$text);
 foreach my $line (@lines) {
  $line = html_to_text_out($line);
  $line =~ s/\\"/&quot;/g;
  print "$line\n";
 }
}

sub api2_ListMailingListsSubs{
        my %OPTS = @_;
        my $listname = $OPTS{'listname'};
	my $cli = getCLI();
        my @result;
        my $subs_array=$cli->ListSubscribers($listname);
	foreach my $sub (@$subs_array) {
		my $SubInfos=$cli->GetSubscriberInfo($listname,$sub); 	
		my $postmode = @$SubInfos{'posts'};
		my $numpost;
		my ($mod1sel,$mod2sel,$mod3sel,$mod4sel,$mod5sel,$modallsel,$unmodsel,$nopostsel)=("","","","","","","","");
		my ($r_feedsel,$r_indexsel,$r_digestsel,$r_nullsel,$r_bannedsel,$r_subscribesel,$r_unsubscribesel) = ("","","","","","","");
		if ($postmode eq "moderateAll") {$modallsel="selected=\"selected\"";}
                elsif ($postmode eq "prohibited") {$nopostsel="selected=\"selected\"";}
		elsif (($postmode =~ /#[0-9]+/) || ($postmode eq "")) {
			$numpost = $postmode;
			$numpost =~ s/#//g;
			if ($postmode eq "") {$numpost = 0;};
                        $unmodsel="selected=\"selected\"";
                }
		elsif (@$SubInfos{'posts'}->[0]) {
		 	$postmode = "next @$SubInfos{'posts'}->[0] moderated";
			if (@$SubInfos{'posts'}->[0] == 1) { $mod1sel="selected=\"selected\"";}
			if (@$SubInfos{'posts'}->[0] == 2) { $mod2sel="selected=\"selected\"";}
			if (@$SubInfos{'posts'}->[0] == 3) { $mod3sel="selected=\"selected\"";}
			if (@$SubInfos{'posts'}->[0] == 4) { $mod4sel="selected=\"selected\"";}
			if (@$SubInfos{'posts'}->[0] == 5) { $mod5sel="selected=\"selected\"";}
                }
		if (@$SubInfos{'mode'} eq "feed") { $r_feedsel="selected=\"selected\"";}
		if (@$SubInfos{'mode'} eq "index") { $r_indexsel="selected=\"selected\"";}
		if (@$SubInfos{'mode'} eq "digest") { $r_digestsel="selected=\"selected\"";}
		if (@$SubInfos{'mode'} eq "null") { $r_nullsel="selected=\"selected\"";}
		if (@$SubInfos{'mode'} eq "banned") { $r_bannedsel="selected=\"selected\"";}
		if (@$SubInfos{'mode'} eq "subscribe") { $r_subscribesel="selected=\"selected\"";}
		if (@$SubInfos{'mode'} eq "unsubscribe") { $r_unsubscribesel="selected=\"selected\"";}
		push (@result, {subemail => "$sub" ,rcvmode => "@$SubInfos{'mode'}", postmode => "$postmode" , mod1sel => "$mod1sel",mod2sel=>"$mod2sel",mod3sel=>"$mod3sel",mod4sel=>"$mod4sel",mod5sel=>"$mod5sel",modallsel=>"$modallsel",unmodsel=>"$unmodsel",nopostsel=>"$nopostsel",r_feedsel=>"$r_feedsel",r_indexsel=>"$r_indexsel",r_digestsel=>"$r_digestsel",r_nullsel=>"$r_nullsel",r_bannedsel=>"$r_bannedsel", numpost=>"$numpost", r_subscribesel=>"$r_subscribesel", r_unsubscribesel=>"$r_unsubscribesel"});

	}
	$cli->Logout();
        return @result;
}       

sub api2_SetSubSettings {
        my %OPTS = @_;
        my $listname = $OPTS{'listname'};
        my $subemail = $OPTS{'subemail'};
        my $CGPMLReceivingMode= $OPTS{'CGPMLReceivingMode'};
        my $CGPMLPostingMode= $OPTS{'CGPMLPostingMode'};
	my $cli = getCLI();
	if ($CGPMLPostingMode eq "mod1") {$CGPMLPostingMode=1;};
	if ($CGPMLPostingMode eq "mod2") {$CGPMLPostingMode=2;};
	if ($CGPMLPostingMode eq "mod3") {$CGPMLPostingMode=3;};
	if ($CGPMLPostingMode eq "mod4") {$CGPMLPostingMode=4;};
	if ($CGPMLPostingMode eq "mod5") {$CGPMLPostingMode=5;};
	if ($CGPMLPostingMode eq "modall") {$CGPMLPostingMode="MODERATEALL";};
	if ($CGPMLPostingMode eq "unmod") {$CGPMLPostingMode="UNMODERATED";};
	if ($CGPMLPostingMode eq "nopost") {$CGPMLPostingMode="PROHIBITED";};
	$cli->SetPostingMode("$listname","$subemail","$CGPMLPostingMode");
	$cli->List("$listname","$CGPMLReceivingMode","$subemail");
        my $error_msg = $cli->getErrMessage();
        if ($error_msg eq "OK") {
                #noop
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg; 
        }               
	$cli->Logout();
        return @result; 

}

sub api2_UnSub {
        my %OPTS = @_;
        my $listname = $OPTS{'listname'};
        my $subemail = $OPTS{'subemail'};
	my $cli = getCLI();
        $cli->List("$listname","unsubscribe","$subemail");
        my $error_msg = $cli->getErrMessage();
        if ($error_msg eq "OK") {
                #noop
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }
	$cli->Logout();
        return @result;

}

sub api2_Sub {
        my %OPTS = @_;
        my $listname = $OPTS{'listname'};
        my $subemail = $OPTS{'subemail'};
        my $CGPMLReceivingMode= $OPTS{'CGPMLReceivingMode'};
        my $CGPMLPostingMode= $OPTS{'CGPMLPostingMode'};
	my $cli = getCLI();
        $cli->List("$listname","$CGPMLReceivingMode","$subemail");
 	if ($CGPMLPostingMode eq "mod1") {$CGPMLPostingMode=1;};
        if ($CGPMLPostingMode eq "mod2") {$CGPMLPostingMode=2;};
        if ($CGPMLPostingMode eq "mod3") {$CGPMLPostingMode=3;};
        if ($CGPMLPostingMode eq "mod4") {$CGPMLPostingMode=4;};
        if ($CGPMLPostingMode eq "mod5") {$CGPMLPostingMode=5;};
        if ($CGPMLPostingMode eq "modall") {$CGPMLPostingMode="MODERATEALL";};
        if ($CGPMLPostingMode eq "unmod") {$CGPMLPostingMode="UNMODERATED";};
        if ($CGPMLPostingMode eq "nopost") {$CGPMLPostingMode="PROHIBITED";};

	$cli->SetPostingMode("$listname","$subemail","$CGPMLPostingMode");
        my $error_msg = $cli->getErrMessage();
        if ($error_msg eq "OK") {
                #noop
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }
	$cli->Logout();
        return @result;
}

sub api2_ListGroups{
        my %OPTS = @_;
        @domains = Cpanel::Email::listmaildomains();
	my $cli = getCLI();
        my @result;
        foreach my $domain (@domains) {
                my $groups=$cli->ListGroups($domain);
                foreach $groupName (sort @$groups) {
                 push( @result, { list => "$groupName\@$domain" , domain =>"$domain"} );
                }
        }
	$cli->Logout();
        return @result;
}

sub api2_DelGroup{
        my %OPTS = @_;
        my $listname = $OPTS{'email'};
	my $cli = getCLI();
        $cli->DeleteGroup("$listname");
        my $error_msg = $cli->getErrMessage();
        my @result;
        if ($error_msg eq "OK") {
                push( @result, { email => "$listname" } );
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }
	$cli->Logout();
        return @result;
}

sub api2_RenameGroup {
        my %OPTS = @_;
        my $email = $OPTS{'email'};
        my $newname = $OPTS{'newname'};
	my $cli = getCLI();
        $cli->RenameGroup("$email","$newname");
        my $error_msg = $cli->getErrMessage();
        my @result;
        if ($error_msg eq "OK") {
                push( @result, { email => "$email" } );
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }
	$cli->Logout();
        return @result;
}



sub api2_AddGroup{
        my %OPTS = @_;
        my $domain = $OPTS{'domain'};
        my $listname = $OPTS{'email'};
        my $spectre = $OPTS{'spectre'};
        my $realname = $OPTS{'realname'};
	my $cli = getCLI();
        $cli->CreateGroup("$listname\@$domain");
        my $error_msg = $cli->getErrMessage();
        my @result;
        if ($error_msg eq "OK") {
                push( @result, { email => "$listname", domain => "$domain" } );
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }

	# set real name
	$Settings=$cli->GetGroup("$listname\@$domain");
  	@$Settings{'RealName'}=$realname; 
  	$cli->SetGroup("$listname\@$domain",$Settings);
	$cli->Logout();


	# Create rule if posting is restricted to members : (spectre = 0)
	if (!$spectre) {
		SetGroupInternal("$listname\@$domain");
	}

        return @result;
}


sub api2_ListGroupMembers {
        my %OPTS = @_;
        my $listname = $OPTS{'listname'};
	my $cli = getCLI();
        my @result;
	my $Settings;
	$Settings=$cli->GetGroup($listname);
        foreach (keys %$Settings) {
      		my $data=@$Settings{$_};
      		if (ref ($data) eq 'ARRAY') {
        		foreach my $member (@$data) {
					push (@result, {subemail => "$member"});
        		}
		}
    	}
	$cli->Logout();
        return @result;
}      


sub api2_AddGroupMember {
        my %OPTS = @_;
        my $listname = $OPTS{'listname'};
        my $subemail = $OPTS{'subemail'};
	if (!$subemail) {
	 $Cpanel::CPERROR{'InputWrong'} = "Group Name must not be empty";
	 return;
	}
        my $domain = $OPTS{'domain'};
	my $cli = getCLI();

	my $Settings=$cli->GetGroup($listname);
  	@$Settings{'Members'}=[] unless(@$Settings{'Members'});
  	my $Members=@$Settings{'Members'};
  	push(@$Members,"$subemail\@$domain");
  	$cli->SetGroup($listname,$Settings);
        my $error_msg = $cli->getErrMessage();
        if ($error_msg eq "OK") {
                #noop
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }
	if (IsGroupInternal($listname)) {
		SetGroupExternal($listname);
		SetGroupInternal($listname);
	}
	$cli->Logout();
        return @result;
}

sub api2_RemoveGroupMember {
        my %OPTS = @_;
        my $listname = $OPTS{'listname'};
        my $subemail = $OPTS{'subemail'};
	my $cli = getCLI();
        
        my $Settings=$cli->GetGroup($listname);
        @$Settings{'Members'}=[] unless(@$Settings{'Members'});
        my $Members=@$Settings{'Members'};
        my $NewMembers=[];
	my $found=0;
	foreach my $member (@$Members) {
         	if ((!($subemail eq $member)) || $found) {push(@$NewMembers,$member);};
		if ($subemail eq $member) {$found=1;}
        }
	@$Settings{'Members'}=$NewMembers;
        $cli->SetGroup($listname,$Settings);
        my $error_msg = $cli->getErrMessage();
        if ($error_msg eq "OK") {
                #noop
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }       
        if (IsGroupInternal($listname)) {
                SetGroupExternal($listname);
                SetGroupInternal($listname);
        }
	$cli->Logout();
        return @result;
}

sub api2_GetGroupSettings {

        my %OPTS = @_;
        my $email = $OPTS{'email'};
	my $cli = getCLI();
        my $listSettings = $cli->GetGroup("$email");
        my $error_msg = $cli->getErrMessage();
        my @result;
        if ($error_msg eq "OK") {
                foreach (keys %$listSettings) {
                        my $key=$_;
                        my $value = @$listSettings{$key};
                        push( @result, { "$key" => "$value" } );
                        $Cpanel::CPDATA{"$key"} = "$value";
             }
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }
	if (IsGroupInternal($email)) {
		push( @result, { "spectre" => "0" } );
                $Cpanel::CPDATA{"spectre"} = "0";
	} else {
		push( @result, { "spectre" => "1" } );
                $Cpanel::CPDATA{"spectre"} = "1";
	}
	$cli->Logout();
        return @result;
}

sub api2_SetAutoresponder {
        my %OPTS = @_;
	my $email = $OPTS{'email'};
	my $cli = getCLI();

	my $body = '+Subject: ' . $OPTS{'subject'} . "\n";
	$body .= "In-Reply-To: ^I\n";
	$body .= "From: " . $OPTS{'from'} . " <" . $OPTS{'email'} . '@' . $OPTS{'domain'} . ">\n\n";
	$body .= $OPTS{'body'};

	my $conditions = [
			  ["Human Generated", "---"],
			  ['From', "not in", "#RepliedAddresses"]
			 ];
	if ($OPTS{'start'}) {
	  my $start = scalar localtime ($OPTS{'start'});
	  $start =~ m/^\w{3}\s+(\w{3})\s+(\d+)\s+(.*?)\s+(\d{4})$/;
	  $start = sprintf('%02d', $2) . " $1 $4 $3";
	  push @$conditions, ["Current Date", "greater than", $start];
	}
	if ($OPTS{'stop'}) {
	  my $stop = scalar localtime ($OPTS{'stop'});
	  $stop =~ m/^\w{3}\s+(\w{3})\s+(\d+)\s+(.*?)\s+(\d{4})$/;
	  $stop = sprintf('%02d', $2) . " $1 $4 $3";
	  push @$conditions, ["Current Date", "less than", $stop];
	}

	my $rule = [2,"#Vacation",$conditions,[
				     [
				      "Reply with",
				      $body
				     ],
				     ["Remember 'From' in", 'RepliedAddresses']
				    ]];

        $cli->UpdateAutoresponder(email => $OPTS{'email'} . '@' . $OPTS{'domain'}, rule => $rule );
        $cli->Logout();
}

sub api2_DeleteAutoresponder {
        my %OPTS = @_;
	my $cli = getCLI();
	my $rule = undef;

        $cli->UpdateAutoresponder(email => $OPTS{'email'}, rule => $rule );
        $cli->Logout();
}

sub api2_ListAutoresponders {
        my %OPTS = @_;

	my @domains = Cpanel::Email::listmaildomains();
	my $cli = getCLI();
	my @result;
        foreach my $domain (@domains) {
                my $accounts=$cli->ListAccounts($domain);
                my $userName;
                foreach $userName (sort keys %$accounts) {      
		  my $account = "$userName\@$domain";
		  if ($OPTS{regex}) {
		    my $qstr = $OPTS{regex};
		    next unless $account =~ /$qstr/;
		  }
		  my $rule = $cli->GetAutoresponder(account => $account);
		  if ( $rule->[0] == 2 ) {
		    my $subject = $rule->[3]->[0]->[1];
		    $subject =~ s/^\+Subject\: (.*?)\\e.*?$/$1/;
		    push( @result, {
				    email => $account, 
				    subject => $subject, 
				    domain => $domain, 
				   });
		  }
		}
	}
	$cli->Logout();
	return @result;
}

sub api2_EditAutoresponder {
  my %OPTS = @_;

  my $cli = getCLI();

  my $account = $OPTS{email};
  if ($OPTS{regex}) {
    my $qstr = $OPTS{regex};
    next unless $account =~ /$qstr/;
  }
  my $rule = $cli->GetAutoresponder(account => $account);
  my $replay = $rule->[3]->[0]->[1];
  $replay =~ m/^\+Subject\: (.*?)\\e.*?\\e\\e(.*?)$/;
  my $subject = $1;
  my $body = $2;
  $body =~ s/\\r\\e/\n/g;
  my $start = undef;
  my $stop = undef;
  for my $condition (@{$rule->[2]}) {
    if ($condition->[0] eq 'Current Date') {
      my %months = (
		    'Jan' => 0,
		    'Feb' => 1,
		    'Mar' => 2,
		    'Apr' => 3,
		    'May' => 4,
		    'Jun' => 5,
		    'Jul' => 6,
		    'Aug' => 7,
		    'Sep' => 8,
		    'Oct' => 9,
		    'Nov' => 10,
		    'Dec' => 11
		   );
      my @date = split " ", $condition->[2];
      if ($condition->[1] eq 'greater than') {
	$start = timelocal_nocheck( $date[5], $date[4], $date[3], $date[0], $months{$date[1]}, ($date[2]-1900) );
      } elsif ($condition->[1] eq 'less than') {
	$stop = timelocal_nocheck( $date[5], $date[4], $date[3], $date[0], $months{$date[1]}, ($date[2]-1900) );
      }
    }
  }
  
  $cli->Logout();
  return {
	  subject => $subject, 
	  body => $body,
	  start => $start,
	  stop => $stop
	 };
}


sub api2_ListForwardersBackups {
    my %OPTS = @_;
    
    my @domains = Cpanel::Email::listmaildomains();
	my $cli = getCLI();
    my @result;
    foreach my $domain (@domains) {
	my $accounts=$cli->ListAccounts($domain);
	my $domainFound = 0;
	foreach my $userName (sort keys %$accounts) {
	    my $Rules=$cli->GetAccountMailRules("$userName\@$domain") || die "Error: ".$cli->getErrMessage.", quitting";
	    foreach my $Rule (@$Rules) {
		if ($Rule->[1] eq "#Redirect" && $Rule->[3]->[0]->[1] ne '' ) {
		    push( @result, {
			domain => $domain
			  } );
		    $domainFound = 1;
		}
		last if $domainFound;
	    }
	    last if $domainFound;
	}
        next if $domainFound;
    }
    $cli->Logout();
    return @result;
}

sub api2_UploadForwarders {
    my $randdata = Cpanel::Rand::getranddata(32);
    $Cpanel::CPVAR{'forwardersimportid'} = $randdata;
    Cpanel::SafeDir::safemkdir( $Cpanel::homedir . '/tmp/forwardersimport', '0700' );
    my @RSD;
    local $Cpanel::IxHash::Modify = 'none';
  FILE:
    foreach my $file ( keys %Cpanel::FORM ) {
        next FILE if $file =~ m/^file-(.*)-key$/;
        next FILE if $file !~ m/^file-(.*)/;
        my $tmpfilepath = $Cpanel::FORM{$file};
        rename( $tmpfilepath, $Cpanel::homedir . '/tmp/forwardersimport/' . $randdata );
        push @RSD, { 'id' => $randdata };
        last;
    }
    return \@RSD;
}

sub api2_RestoreForwarders {
    my %OPTS = @_;
    my @domains = Cpanel::Email::listmaildomains();
    my $cli = getCLI();
    my @result;
    my $gzfile = $Cpanel::homedir . '/tmp/forwardersimport/' . $Cpanel::CPVAR{'forwardersimportid'};
    open(IN, "gunzip -c $gzfile |") || die "can't open pipe to $file";
    my @input = <IN>;
    close IN;
    unlink $gzfile;
    foreach my $domain (@domains) {
	for my $row (@input) {
	    if ( $row =~ m/\@$domain\:/i ) {
		my ($email, $fwdemail) = split '[\:\s]+', $row, 2;
		my ($userName, undef) = split '@', $email;
		chomp $fwdemail;
		addforward(
		    domain => $domain,
		    email => $userName,
		    fwdemail => $fwdemail,
		    cli => $cli
		    );
		push @result, {row => $row};
	    }
	}
    }
    $cli->Logout();
    return @result;
}

sub api2_RestoreFilters {
    my %OPTS = @_;
    
    my @domains = Cpanel::Email::listmaildomains();
    my $cli = getCLI();
    my @result;
    my $file = $Cpanel::homedir . '/tmp/forwardersimport/' . $Cpanel::CPVAR{'forwardersimportid'};
    open (FI, "<", $file);
    my @yaml = <FI>;
    my $yaml = join "", @yaml;
    close FI;
    unlink $file;
    my $loaded_data = YAML::Syck::Load($yaml);
    $loaded_data = $loaded_data->[0];
    foreach my $domain (@domains) {
	my $accounts = $cli->ListAccounts($domain);
	my $apiref = Cpanel::Api2::Exec::api2_preexec( 'Email', 'storefilter' );
	foreach my $userName (sort keys %$accounts) {
	    if ($loaded_data->{"$userName\@$domain"}) {
		for my $filter (@{$loaded_data->{"$userName\@$domain"}}) {
		    # Import filters per account
		    my $rules = $cli->GetAccountMailRules("$userName\@$domain");
		    if ($rules) {
			# Fake filter in cPanel
			my ( $data, $status ) = Cpanel::Api2::Exec::api2_exec( 'Email', 'storefilter', $apiref, {account=> "$userName\@$domain",filtername=> $filter->[1], action1=> 'fail', match1=> 'is', opt1 => 'or', part1 => '$header_to:', val1 => 'noone@example.com', oldfiltername => $filter->[1]} );
			# Real CGPro filter
			my $newrules = [];
			my $found = 0;
			for my $rule (@$rules) {
			    if ($rule->[1] eq $filter->[1]) {
				push @$newrules, $filter;
				$found = 1;
			    } else {
				push @$newrules, $rule;
			    }
			}
			push @$newrules, $filter unless $found;
			$cli->SetAccountMailRules("$userName\@$domain",$newrules);
		    }
		    # END import filters
		    push @result, {row, "$userName\@$domain: " . $filter->[1] . "\n"};
		}
	    }
	}
    }
    $cli->Logout();
    return @result;
}

sub api2_ListAccountsBackups {
    my %OPTS = @_;
    
    my @domains = Cpanel::Email::listmaildomains();
	my $cli = getCLI();
    my @result;
    foreach my $domain (@domains) {
	my $accounts=$cli->ListAccounts($domain);
	foreach my $userName (sort keys %$accounts) {
	    push( @result, {
		domain => $domain
		  } );
	    last;
	}
    }
    $cli->Logout();
    return @result;
}

sub api2_GetAccountsBackups {
    my %OPTS = @_;
	my $cli = getCLI();
    my $domain = $OPTS{'domain'};
    my $accounts=$cli->ListAccounts($domain);
    my @result;
    foreach my $userName (sort keys %$accounts) {      
	my $accountData = $cli->GetAccountEffectiveSettings("$userName\@$domain");
	my $pass = $cli->GetAccountPlainPassword("$userName\@$domain");
	my $diskquota = @$accountData{'MaxAccountSize'} || '';
	$diskquota =~ s/M//g;
	push( @result, {
	    email => "$userName\@$domain", 
	    diskquota => "$diskquota", 
	    pass => "$pass"
 	      } );
    }
    $cli->Logout();
    return @result;
}

sub api2_UninstallSRVXMPP {
    my %OPTS = @_;
    my @domains = Cpanel::Email::listmaildomains();
    my $locale = Cpanel::Locale->get_handle();
    my @results;
     for my $domain (@domains) {
	my $result = Cpanel::AdminBin::adminrun( 'cca', "UNINSTALLSRVXMPP", $domain);
	chomp $result;
	if ( $result eq '.' ) {
	    push @results, { 'uninstalled' => $locale->maketext('XMPP records disabled.') };
	} else {
	    push @results, { 'uninstalled' => $locale->maketext( 'XMPP records not disabled ([_1]).', $result ) };
	}
    }
    return @results;
}

sub api2_InstallSRVXMPP {
    my %OPTS = @_;
    my @domains = Cpanel::Email::listmaildomains();
    my $locale = Cpanel::Locale->get_handle();
    my @results;
     for my $domain (@domains) {
	my $result = Cpanel::AdminBin::adminrun( 'cca', "INSTALLSRVXMPP", $domain);
	chomp $result;
	if ( $result eq '.' ) {
	    push @results, { 'installed' => $locale->maketext('XMPP records enabled.') };
	} else {
	    push @results, { 'installed' => $locale->maketext( 'XMPP records not enabled ([_1]).', $result ) };
	}
    }
    return @results;
}

sub api2_UninstallSRVSIP {
    my %OPTS = @_;
    my @domains = Cpanel::Email::listmaildomains();
    my $locale = Cpanel::Locale->get_handle();
    my @results;
     for my $domain (@domains) {
	my $result = Cpanel::AdminBin::adminrun( 'cca', "UNINSTALLSRVSIP", $domain);
	chomp $result;
	if ( $result eq '.' ) {
	    push @results, { 'uninstalled' => $locale->maketext('SIP records disabled.') };
	} else {
	    push @results, { 'uninstalled' => $locale->maketext( 'SIP records not disabled ([_1]).', $result ) };
	}
    }
    return @results;
}

sub api2_InstallSRVSIP {
    my %OPTS = @_;
    my @domains = Cpanel::Email::listmaildomains();
    my $locale = Cpanel::Locale->get_handle();
    my @results;
     for my $domain (@domains) {
	my $result = Cpanel::AdminBin::adminrun( 'cca', "INSTALLSRVSIP", $domain);
	chomp $result;
	if ( $result eq '.' ) {
	    push @results, { 'installed' => $locale->maketext('SIP records enabled.') };
	} else {
	    push @results, { 'installed' => $locale->maketext( 'SIP records not enabled ([_1]).', $result ) };
	}
    }
    return @results;
}

sub api2_UninstallSRVCALDAV {
    my %OPTS = @_;
    my @domains = Cpanel::Email::listmaildomains();
    my $locale = Cpanel::Locale->get_handle();
    my @results;
     for my $domain (@domains) {
	my $result = Cpanel::AdminBin::adminrun( 'cca', "UNINSTALLSRVCALDAV", $domain);
	chomp $result;
	if ( $result eq '.' ) {
	    push @results, { 'uninstalled' => $locale->maketext('CALDAV records disabled.') };
	} else {
	    push @results, { 'uninstalled' => $locale->maketext( 'CALDAV records not disabled ([_1]).', $result ) };
	}
    }
    return @results;
}

sub api2_InstallSRVCALDAV {
    my %OPTS = @_;
    my @domains = Cpanel::Email::listmaildomains();
    my $locale = Cpanel::Locale->get_handle();
    my @results;
     for my $domain (@domains) {
	my $result = Cpanel::AdminBin::adminrun( 'cca', "INSTALLSRVCALDAV", $domain);
	chomp $result;
	if ( $result eq '.' ) {
	    push @results, { 'installed' => $locale->maketext('CALDAV records enabled.') };
	} else {
	    push @results, { 'installed' => $locale->maketext( 'CALDAV records not enabled ([_1]).', $result ) };
	}
    }
    return @results;
}

sub api2_UninstallSRVCARDDAV {
    my %OPTS = @_;
    my @domains = Cpanel::Email::listmaildomains();
    my $locale = Cpanel::Locale->get_handle();
    my @results;
     for my $domain (@domains) {
	my $result = Cpanel::AdminBin::adminrun( 'cca', "UNINSTALLSRVCARDDAV", $domain);
	chomp $result;
	if ( $result eq '.' ) {
	    push @results, { 'uninstalled' => $locale->maketext('CARDDAV records disabled.') };
	} else {
	    push @results, { 'uninstalled' => $locale->maketext( 'CARDDAV records not disabled ([_1]).', $result ) };
	}
    }
    return @results;
}

sub api2_InstallSRVCARDDAV {
    my %OPTS = @_;
    my @domains = Cpanel::Email::listmaildomains();
    my $locale = Cpanel::Locale->get_handle();
    my @results;
     for my $domain (@domains) {
	my $result = Cpanel::AdminBin::adminrun( 'cca', "INSTALLSRVCARDDAV", $domain);
	chomp $result;
	if ( $result eq '.' ) {
	    push @results, { 'installed' => $locale->maketext('CARDDAV records enabled.') };
	} else {
	    push @results, { 'installed' => $locale->maketext( 'CARDDAV records not enabled ([_1]).', $result ) };
	}
    }
    return @results;
}

sub api2_GetSRV {
    my %OPTS = @_;
    my @domains = Cpanel::Email::listmaildomains();
    my $locale = Cpanel::Locale->get_handle();
    my @results;
     for my $domain (@domains) {
	my $result = Cpanel::AdminBin::adminrun( 'cca', "GETSRV", $domain);
	chomp $result;
	if ( $result =~ /^\./ ) {
	    push @results, { 'data' => 'OK' };
	    $Cpanel::CPVAR{"xmpp_enabled"} = 0;
	    $Cpanel::CPVAR{"xmpp_enabled"} = 1 if $result =~ m/_xmpp\-/;
	    $Cpanel::CPVAR{"sip_enabled"} = 0;
	    $Cpanel::CPVAR{"sip_enabled"} = 1 if $result =~ m/_sip/;
	    $Cpanel::CPVAR{"caldav_enabled"} = 0;
	    $Cpanel::CPVAR{"caldav_enabled"} = 1 if $result =~ m/_caldav/;
	    $Cpanel::CPVAR{"carddav_enabled"} = 0;
	    $Cpanel::CPVAR{"carddav_enabled"} = 1 if $result =~ m/_carddav/;
	} else {
	    push @results, { 'data' =>  $result };
	}
    }
    return @results;
}

sub api2_SetGroupSettings {
        my %OPTS = @_;
        my $email = $OPTS{'email'};
	my $cli = getCLI();

        $Settings=$cli->GetGroup($email);
        @$Settings{'RealName'}=$OPTS{'RealName'};
        @$Settings{'RemoveToAndCc'}=($OPTS{'RemoveToAndCc'}?'YES':'NO');;
        @$Settings{'Expand'}=($OPTS{'Expand'}?'YES':'NO');;
        @$Settings{'FinalDelivery'}=($OPTS{'FinalDelivery'}?'YES':'NO');;
        @$Settings{'RejectAutomatic'}=($OPTS{'RejectAutomatic'}?'YES':'NO');;
        @$Settings{'RemoveAuthor'}=($OPTS{'RemoveAuthor'}?'YES':'NO');;
        @$Settings{'SetReplyTo'}=($OPTS{'SetReplyTo'}?'YES':'NO');;
        $cli->SetGroup($email,$Settings);
        my $error_msg = $cli->getErrMessage();
        my @result;
        if ($error_msg eq "OK") {
                #noop
        } else {
                $Cpanel::CPERROR{'CommuniGate'} = $error_msg;
        }
	$cli->Logout();
	if ($OPTS{'spectre'} && IsGroupInternal($email)) {
		SetGroupExternal($email);
	}
	if (!$OPTS{'spectre'} && (!IsGroupInternal($email))) {
                SetGroupInternal($email);
        } 

        return @result;
}

sub api2_storefilter {
    my %OPTS = @_;
    my $formdump = $OPTS{'formdump'};
    my $params = {};
    for my $row (split "\n", $formdump) {
	if ($row =~ m/^(\S+)\s\=\s(.*?)$/) {
	    my $key =$1;
	    my $value = $2;
	    if ($key =~ m/^(\S+)(\d+)$/) {
		$params->{$1}->[$2 - 1] = $value;
	    } else {
		$params->{$key} = $value;
	    }
	}
    }
    my $cli = getCLI();
    my $rules = $cli->GetAccountMailRules($params->{account});
    if ($rules) {
	my $conditions = [];
	my $actions = [];
	for (my $i = 0; $i <= $#{$params->{part}}; $i++) {
	    push @$conditions, [$params->{part}->[$i], $params->{match}->[$i], $params->{val}->[$i]];
	}
	for (my $i = 0; $i <= $#{$params->{action}}; $i++) {
	    my $action = [$params->{action}->[$i]];
	    push @$action, $params->{dest}->[$i] if $params->{dest}->[$i];
	    push @$actions, $action;
	}
	my $therule = [
	    5,
	    $params->{filtername},
	    $conditions,
	    $actions
	    ];
	my $newrules = [];
	my $found = 0;
	for my $rule (@$rules) {
	    if ($rule->[1] eq $params->{oldfiltername}) {
		push @$newrules, $therule;
		$found = 1;
	    } else {
		push @$newrules, $rule;
	    }
	}
	push @$newrules, $therule unless $found;
	$cli->SetAccountMailRules($params->{account},$newrules);
    }
    $cli->Logout();
    return;
}
sub api2_get_filter {
    my %OPTS = @_;
    my $cli = getCLI();
    my $rules = $cli->GetAccountMailRules($OPTS{account});
	for my $rule (@$rules) {
	    if ($rule->[1] eq $OPTS{filtername}) {
		my $filter = {};
		$filter->{data}->{filtername} = $rule->[1];
		for my $condition (@{$rule->[2]}) {
		    push @{$filter->{data}->{rules}}, {part => $condition->[0], match => $condition->[1], val => $condition->[2]};
		}
		for my $action (@{$rule->[3]}) {
		    push @{$filter->{data}->{actions}}, {action => $action->[0], dest => $action->[1]};
		}
		
		$cli->Logout();
		return {get_filter => $filter};
	    }
	}
    $cli->Logout();
    return { get_filter => { data => { filtername => "Rule 1", actions => [{}], rules => [{}] } } };
}

sub api2_dumpfilters {
    my %OPTS = @_;
    my $cli = getCLI();
    my @domains = Cpanel::Email::listmaildomains();
    my $filters = {};
    for my $domain (@domains) {
	my $accounts = $cli->ListAccounts($domain);
	for my $account (sort keys %$accounts) {
	    $filters->{"$account\@$domain"} = [];
	    my $rules = $cli->GetAccountMailRules("$account\@$domain");
	    for my $rule (@$rules) {
		push @{$filters->{"$account\@$domain"}}, $rule if $rule->[1] !~ m/^#/;
	    } 
	}
    }
    $cli->Logout();
    return $filters;
}

sub api2_get_archiving_configuration {
    my $cli = getCLI();
    my @domains = Cpanel::Email::listmaildomains();
    my $filters = {};
    my @result;
    for my $domain (@domains) {
	my $defaults = $cli->GetAccountDefaults($domain);
	push @result, { domain => $domain, ArchiveMessagesAfter => $defaults->{'ArchiveMessagesAfter'}, DeleteMessagesAfter => $defaults->{'DeleteMessagesAfter'}} if $defaults;
    }
    $cli->Logout();
    return @result;
}

sub api2_updatearchive {
    my %OPTS = @_;
    my $formdump = $OPTS{'formdump'};
    my $params = {};
    for my $row (split "\n", $formdump) {
	if ($row =~ m/^(\S+)\s\=\s(.*?)$/) {
	    my $key =$1;
	    my $value = $2;
	    if ($key =~ m/^(\S+)(\d+)$/) {
		$params->{$1}->[$2 - 1] = $value;
	    } else {
		$params->{$key} = $value;
	    }
	}
    }
    my $cli = getCLI();
    my @domains = Cpanel::Email::listmaildomains();
    for my $domain (@domains) {
	$cli->UpdateAccountDefaults(domain => $domain, settings => {
	    ArchiveMessagesAfter => ((defined $params->{'ArchiveMessagesAfter-' . $domain})?$params->{'ArchiveMessagesAfter-' . $domain}:undef),
	    DeleteMessagesAfter => ((defined $params->{'DeleteMessagesAfter-' . $domain})?$params->{'DeleteMessagesAfter-' . $domain}:undef )
				    });
    }
    $cli->Logout();
    return {msg => "Changes saved."};
}

sub api2_VerifyAccount {
    my %OPTS = @_;
    my $user = $OPTS{'email'};
    my $domain = $OPTS{'domain'};
    my $cli = "";
    my $settings = "";
    eval { 
	$cli = getCLI();
	$settings = $cli->GetAccountSettings("$user\@$domain");
    };
    unless ($settings) {
    	my $apiref = Cpanel::Api2::Exec::api2_preexec( 'Email', 'delpop' );
    	my ( $data, $status ) = Cpanel::Api2::Exec::api2_exec( 'Email', 'delpop', $apiref, {domain => $domain, email=> $user} );
    }
    $cli->Logout();
    return;
}

sub api2_checkSSLlinks {
    $Cpanel::CPVAR{"ssllinks"} = 0;
    $Cpanel::CPVAR{"ssllinks"} = 1 if -f "/var/cpanel/cgpro/ssllinks";
}

sub api2_DKIMVerification {
    my %OPTS = @_;
    $cli = getCLI();
    if ($OPTS{DKIMVerifyReject}) {
	for my $domain (@domains) {
	    my $settings = {
		'DKIMVerifyEnable' => ($OPTS{DKIMVerifyEnable} ? 'YES' : 'NO'),
		'DKIMVerifyReject' => $OPTS{DKIMVerifyReject}
	    };
	    $cli->UpdateAccountDefaultPrefs(domain => $domain, settings => $settings);
	}
    }
    my $serverPrefs = $cli->GetServerAccountPrefs();
    $Cpanel::CPVAR{"serverPrefsEnable"} = $serverPrefs->{DKIMVerifyEnable};
    $Cpanel::CPVAR{"serverPrefsReject"} = $serverPrefs->{DKIMVerifyReject};
    my @domains = Cpanel::Email::listmaildomains();
    my $domainPrefs = $cli->GetAccountDefaultPrefs($domains[0]);
    $Cpanel::CPVAR{"domainPrefsEnable"} = $domainPrefs->{DKIMVerifyEnable};
    $Cpanel::CPVAR{"domainPrefsReject"} = $domainPrefs->{DKIMVerifyReject};
    $cli->Logout();
}

sub api2_EditContact {
    my %OPTS = @_;
    my $account = $OPTS{'account'};
    my (undef,$dom) = split "@", $account;
    my @domains = Cpanel::Email::listmaildomains();
    my $cli = getCLI();
    my $locale = Cpanel::Locale->get_handle();
    my @return;
    for my $domain (@domains) {
	if ($domain eq $dom) {
	    $password = $cli->GetAccountPlainPassword($account);
	    if ($password) {
		my $ximss = getXIMSS($account, $password);
		my $time = time();
		$ximss->send({folderOpen => {
		        id => "$time-mailbox",
			folder => $OPTS{'box'},
			    sortField => "To"
			      }});
		my $mailbox = $ximss->parseResponse("$time-mailbox");
		if ($mailbox->{'folderReport'}) {
		        $ximss->send(
			    {
				folderBrowse => {
				    id => "$time-messages",
				    folder => $OPTS{'box'},
				    index => {
					    from => 0,
					    till => ($mailbox->{'folderReport'}->{'messages'})
				    }
				}
			    });
			my $messages = $ximss->parseResponse("$time-messages");
			if ($messages->{'folderReport'}) {
			    $ximss->send({folderRead => {
				    id => "$time-contact",
				    folder => $OPTS{'box'},
				    UID => $OPTS{'UID'},
				        totalSizeLimit => 5000
					  }});
			    my $contact = $ximss->parseResponse("$time-contact");
			    if ($contact->{'folderMessage'}) {
				$ximss->send({folderClose => {id => "$time-close", folder=>$OPTS{'box'}}});
				$ximss->close();
				my @localtime = localtime(time);
				$cli->Logout();
				return {
				    vcard => $contact->{folderMessage}->{EMail}->{MIME}->{vCard},
				    contact => $contact,
				    YEAR => ($localtime[5] + 1900),
				    forceArray => \&forceArray
				}
			    }
			}
		}
		$ximss->send({folderClose => {id => "$time-close", folder=>$OPTS{'box'}}});
		$ximss->close();
	    }
	    last;
	}
    }
    $cli->Logout();
    return @return;
}

sub api2_ListContacts {
    my %OPTS = @_;
    my $account = $OPTS{'account'};
    my (undef,$dom) = split "@", $account;
    my @domains = Cpanel::Email::listmaildomains();
    my $cli = getCLI();
    my $locale = Cpanel::Locale->get_handle();
    my $contacts;
    for my $domain (@domains) {
	if ($domain eq $dom) {
	    $password = $cli->GetAccountPlainPassword($account);
	    if ($password) {
		my $boxes = $cli->ListMailboxes(accountName => $account);
		for my $box (keys %$boxes) {
		    delete $boxes->{$box} unless $boxes->{$box}->{'Class'} eq 'IPF.Contact';
		}
		my $ximss = getXIMSS($account, $password);

		for my $box (keys %$boxes) {
		    my $time = time();
		    $ximss->send({folderOpen => {
			id => "$time-mailbox",
			folder => $box,
			sortField => "To"
				  }});
		    my $mailbox = $ximss->parseResponse("$time-mailbox");
		    if ($mailbox->{'folderReport'}) {
			$ximss->send(
			    {
				folderBrowse => {
				        id => "$time-messages",
					    folder => $box,
					index => {
					    from => 0,
					    till => ($mailbox->{'folderReport'}->{'messages'})
					}
				}
			    });
			my $messages = $ximss->parseResponse("$time-messages");
			if ($messages->{'folderReport'}) {
			    $contacts->{$box} = [] unless $contacts->{$box};
			    for my $message (@{forceArray($messages->{'folderReport'})}) {
				$ximss->send({folderRead => {
				        id => "$time-contact",
					    folder => $box,
					UID => $message->{"UID"},
					    totalSizeLimit => 5000
					      }});
				my $contact = $ximss->parseResponse("$time-contact");
				if ($contact->{'folderMessage'}) {
				    if (defined $contact->{'folderMessage'}->{EMail}->{MIME}->{vCardGroup}) {
					push @{$contacts->{$box}}, {
					    name => $contact->{'folderMessage'}->{EMail}->{MIME}->{vCardGroup}->{FN}->{VALUE},
					        group => 1,
					    uid => $message->{UID}
					};
				    } else {
					push @{$contacts->{$box}}, {
					    email => [map {{ value => $_->{VALUE}, type => [keys(%$_)] }} @{forceArray( $contact->{'folderMessage'}->{EMail}->{MIME}->{vCard}->{EMAIL} )}],
					    tel => [map {{ value => $_->{VALUE}, type => [keys(%$_)] }} @{forceArray( $contact->{'folderMessage'}->{EMail}->{MIME}->{vCard}->{TEL} )}],
					    name => $contact->{'folderMessage'}->{EMail}->{MIME}->{vCard}->{FN}->{VALUE},
					    uid => $message->{UID}
					};
				    }
				}
			    }
			}
		    }
		}
		$ximss->close();
		my $prefs = $cli->GetAccountEffectivePrefs($account);
		$cli->Logout();
		return {contacts => $contacts, account => $OPTS{'account'}, boxes => $boxes, prefs => $prefs};
	    }
	    last;
	}
    }
    $cli->Logout();
    return undef;
}

sub api2_DoEditContact {
    my %OPTS = @_;
    my $formdump = $OPTS{'formdump'};
    my $params = {};
    for my $row (split "\n", $formdump) {
	if ($row =~ m/^(\S+)\s\=\s(.*?)$/) {
	    my $key =$1;
	    my $value = $2;
	    $params->{$key} = $value;
	}
    }
    my $message = {};
    if ($params->{save}) {
	my (undef,$dom) = split "@", $params->{account};
	my @domains = Cpanel::Email::listmaildomains();
	my $cli = getCLI();
	my $locale = Cpanel::Locale->get_handle();
	my @return;
	for my $domain (@domains) {
	    if ($domain eq $dom) {
		$password = $cli->GetAccountPlainPassword($params->{account});
		if ($password) {
		    my $boxes = $cli->ListMailboxes(accountName => $params->{account});
		    for my $box (keys %$boxes) {
			delete $boxes->{$box} unless $boxes->{$box}->{'Class'} eq 'IPF.Contact';
		    }
		    unless (scalar keys %$boxes) {
			$cli->CreateMailbox($params->{account}, $params->{'box'}, undef, 'IPF.Contact');
		    }
		    $message = {};
		    $message->{"FN"} = [join(" ", grep(/.+/, ($params->{FAMILY}, $params->{GIVEN}, $params->{MIDDLE}) ) )];
		    $message->{"X-FILE-AS"} = [join(" ", grep(/.+/, ($params->{FAMILY}, $params->{GIVEN}, $params->{MIDDLE}) ) )];
		    $message->{"N"}->{"GIVEN"} = [$params->{GIVEN}] if $params->{GIVEN};
		    $message->{"N"}->{"MIDDLE"} = [$params->{MIDDLE}] if $params->{MIDDLE};
		    $message->{"N"}->{"FAMILY"} = [$params->{FAMILY}] if $params->{FAMILY};

		        # $message->{EMail}->{'Organization'} = [join(", ", grep(/.+/, ($params->{ORGNAME}, $params->{ORGUNIT}) ) )] if $params->{ORGNAME} && $params->{ORGUNIT};
		    $message->{"ORG"}->{"ORGNAME"} = [$params->{ORGNAME}] if $params->{ORGNAME};
		    $message->{"ORG"}->{"ORGUNIT"} = [$params->{ORGUNIT}] if $params->{ORGUNIT};

		    $message->{"TITLE"}->{"VALUE"} = [$params->{TITLE}] if $params->{TITLE};

		    $message->{"BDAY"}->{"VALUE"} = [join("-", ($params->{BYEAR}, $params->{BMONTH}, $params->{BDAY} ) )] if $params->{BYEAR} && $params->{BMONTH} && $params->{BDAY};

		    $message->{"NICKNAME"}->{"VALUE"} = [$params->{NICKNAME}] if $params->{NICKNAME};
		    $message->{"ROLE"}->{"VALUE"} = [$params->{ROLE}] if $params->{ROLE};
		    $message->{"TZ"}->{"VALUE"} = [$params->{TZ}] if $params->{TZ};
		    $message->{"GEO"}->{"VALUE"} = [$params->{GEO}] if $params->{GEO};
		    $message->{"NOTE"}->{"VALUE"} = [$params->{NOTE}] if $params->{NOTE};
		        
		    my $newUID = join ".", map{ join "", map { int rand(9) } 1..$_} (10,1);
		    $newUID .= "." . $params->{account};
		    $message->{"UID"}->{"VALUE"} = [$params->{oldMessageID} ? $params->{oldMessageID} : $newUID];

		    my $emails = [];
		    for (my $i = 0; $i < $params->{emailcount}; $i++) {
			if ($params->{"mail-$i"} && $params->{"mailtype-$i"}) {
			    push @$emails, {
				VALUE => [$params->{"mail-$i"}],
				USERID => [$params->{"mail-$i"}],
				$params->{"mailtype-$i"} => {}
			    };
			}
		    }
		    $message->{'EMAIL'} = $emails if $#{$emails} >= 0;

		    my $tels = [];
		    for (my $i = 0; $i < $params->{telcount}; $i++) {
			if ($params->{"TEL-$i"} && $params->{"teltype-$i"}) {
			    push @$tels, {
				VALUE => [$params->{"TEL-$i"}],
				NUMBER => [$params->{"TEL-$i"}],
				$params->{"teltype-$i"} => {}
			    };
			}
		    }
		    $message->{'TEL'} = $tels if $#{$tels} >= 0;

		    my $url = [];
		    for (my $i = 0; $i < $params->{wwwcount}; $i++) {
			if ($params->{"URL-$i"} && $params->{"urltype-$i"}) {
			    push @$url, {
				VALUE => [$params->{"URL-$i"}],
				$params->{"urltype-$i"} => {}
			    };
			}
		    }
		    $message->{'URL'} = $url if $#{$url} >= 0;

		    my $address = [];
		    for (my $i = 0; $i < $params->{addresscount}; $i++) {
			if ($params->{"LOCALITY-$i"} && $params->{"addresstype-$i"}) {
			    push @$address, {
				STREET => [$params->{"STREET-$i"}],
				REGION => [$params->{"REGION-$i"}],
				LOCALITY => [$params->{"LOCALITY-$i"}],
				POBOX => [$params->{"POBOX-$i"}],
				CTRY => [$params->{"CTRY-$i"}],
				PCODE => [$params->{"PCODE-$i"}],
				$params->{"addresstype-$i"} => {}
			    };
			}
		    }
		    $message->{'ADR'} = $address if $#{$address} >= 0;

		    my $time = time();
		    my $ximss = getXIMSS($params->{account}, $password);

		    $ximss->send({folderOpen => {
			id => "$time-mailbox",
			folder => $params->{'box'},
			sortField => "To"
				  }});
		    my $mailbox = $ximss->parseResponse("$time-mailbox");
		    if ($mailbox->{'folderReport'}) {
			my $contact = {
			        id => "$time-append",
				folder => $params->{'box'},
				    vCard => $message
			};
			if ($params->{oldUID}) {
			    $contact->{'replacesUID'} = $params->{oldUID};
			    $contact->{'checkOld'} = 'yes';
			}
			$ximss->send({contactAppend => $contact});
			my $append = $ximss->parseResponse("$time-append");
			$Cpanel::CPERROR{'CommuniGate'} = $append->{response}->{errorText} if $append->{response}->{errorText};
		    }
		    $ximss->send({folderClose => {id => "$time-close", folder=>$params->{'box'}}});
		    $ximss->close();
		}
	    }
	}
    }
    return;
}

sub api2_DeleteContact {
    my %OPTS = @_;
    my $account = $OPTS{'account'};
    my (undef,$dom) = split "@", $account;
    my @domains = Cpanel::Email::listmaildomains();
    my $cli = getCLI();
    my @return;
    for my $domain (@domains) {
	if ($domain eq $dom) {
	    $password = $cli->GetAccountPlainPassword($account);
	    if ($password) {
		my $time = time();
		my $ximss = getXIMSS($account, $password);
		$ximss->send({folderOpen => {
		        id => "$time-mailbox",
			folder => $OPTS{'box'},
			    sortField => "To"
			      }});
		my $mailbox = $ximss->parseResponse("$time-mailbox");
		if ($mailbox->{'folderReport'}) {
		    $ximss->send({messageRemove => {
			id => "$time-remove",
			folder => $OPTS{'box'},
			mode => "Immediately",
			UID => [$OPTS{"uid"}]
				  }});
		    $ximss->parseResponse("$time-remove");
		}
		$ximss->send({folderClose => {id => "$time-close", folder=>$OPTS{'box'}}});
		$ximss->send({bye => {id => "$time-bye"}});
	    } else {
		# Error! Cannot fetch contacts;
	    }
	    last;
	}
    }
    $cli->Logout();
    return 1;
}
sub api2_AddContactsBox {
    my %OPTS = @_;
    my $account = $OPTS{'account'};
    my $box = $OPTS{'box'};
    my (undef,$dom) = split "@", $account;
    my @domains = Cpanel::Email::listmaildomains();
    my $cli = getCLI();
    my @return;
    for my $domain (@domains) {
	if ($domain eq $dom) {
	    $cli->CreateMailbox($account, $box, undef, 'IPF.Contact');
	}
    }
    my $error_msg = $cli->getErrMessage();
    $Cpanel::CPERROR{'CommuniGate'} = $error_msg unless ($error_msg eq "OK");
    $cli->Logout();
    return;
}
sub api2_SetDefaultContactsBox {
    my %OPTS = @_;
    my $account = $OPTS{'account'};
    my $box = $OPTS{'box'};
    my (undef,$dom) = split "@", $account;
    my @domains = Cpanel::Email::listmaildomains();
    my $cli = getCLI();
    my @return;
    for my $domain (@domains) {
	if ($domain eq $dom) {
	    $cli->UpdateAccountPrefs($account, {ContactsBox => $box});
	}
    }
    my $error_msg = $cli->getErrMessage();
    $Cpanel::CPERROR{'CommuniGate'} = $error_msg unless ($error_msg eq "OK");
    $cli->Logout();
    return;
}
sub api2_EditContactsGroup {
    my %OPTS = @_;
    my $account = $OPTS{'account'};
    my (undef,$dom) = split "@", $account;
    my @domains = Cpanel::Email::listmaildomains();
    my $cli = getCLI();
    my $locale = Cpanel::Locale->get_handle();
    my @return;
    my $contacts = [];
    my $vcard;
    for my $domain (@domains) {
	if ($domain eq $dom) {
	    $password = $cli->GetAccountPlainPassword($account);
	    if ($password) {
		my $ximss = getXIMSS($account, $password);
		my $time = time();
		$ximss->send({folderOpen => {
		        id => "$time-mailbox",
			folder => $OPTS{'box'},
			    sortField => "To"
			      }});
		my $mailbox = $ximss->parseResponse("$time-mailbox");
		if ($mailbox->{'folderReport'}) {
		        $ximss->send(
			    {
				folderBrowse => {
				    id => "$time-messages",
				    folder => $OPTS{'box'},
				    index => {
					    from => 0,
					    till => ($mailbox->{'folderReport'}->{'messages'})
				    }
				}
			    });
			my $messages = $ximss->parseResponse("$time-messages");
			if ($messages->{'folderReport'}) {
			    for my $message (@{forceArray($messages->{'folderReport'})}) {
				$ximss->send({folderRead => {
				    id => "$time-contact",
				    folder => $OPTS{box},
				    UID => $message->{"UID"},
				    totalSizeLimit => 5000
					      }});
				my $contact = $ximss->parseResponse("$time-contact");
				if ($contact->{'folderMessage'} && defined $contact->{'folderMessage'}->{EMail}->{MIME}->{vCard}) {
				    push @{$contacts}, {
					email => forceArray($contact->{'folderMessage'}->{EMail}->{MIME}->{vCard}->{EMAIL}),
					name => $contact->{'folderMessage'}->{EMail}->{MIME}->{vCard}->{FN}->{VALUE},
				    };
				}
			    }
			    $ximss->send({folderRead => {
				    id => "$time-contact",
				    folder => $OPTS{'box'},
				    UID => $OPTS{'UID'},
				        totalSizeLimit => 5000
					  }});
			    my $contact = $ximss->parseResponse("$time-contact");
			    if ($contact->{'folderMessage'}) {
				$vcard = $contact->{folderMessage}->{EMail}->{MIME}->{vCardGroup};
			    }
			}
		}
		$ximss->send({folderClose => {id => "$time-close", folder=>$OPTS{'box'}}});
		$ximss->close();
		$cli->Logout();
		return {contacts => $contacts, vcard => $vcard, allmails => join(",", map { $_->{VALUE} } @{forceArray($vcard->{MEMBER})} ), forceArray => \&forceArray};
	    }
	    last;
	}
    }
    $cli->Logout();
    return @return;
}
sub api2_DoEditContactsGroup {
    my %OPTS = @_;
    my $formdump = $OPTS{'formdump'};
    my $params = {};
    for my $row (split "\n", $formdump) {
	if ($row =~ m/^(\S+)\s\=\s(.*?)$/) {
    my $key =$1;
    my $value = $2;
    $params->{$key} = $value;
	}
    }
    my $message = {};
    if ($params->{save} && $params->{NAME}) {
	my (undef,$dom) = split "@", $params->{account};
	my @domains = Cpanel::Email::listmaildomains();
	my $cli = getCLI();
	my $locale = Cpanel::Locale->get_handle();
	my @return;
	for my $domain (@domains) {
	    if ($domain eq $dom) {
		$password = $cli->GetAccountPlainPassword($params->{account});
		if ($password) {
		    my $boxes = $cli->ListMailboxes(accountName => $params->{account});
		    for my $box (keys %$boxes) {
			delete $boxes->{$box} unless $boxes->{$box}->{'Class'} eq 'IPF.Contact';
		    }
		    unless (scalar keys %$boxes) {
			$cli->CreateMailbox($params->{account}, $params->{'box'}, undef, 'IPF.Contact');
		    }
		    $message = {};
		    my $members = [map {[split '\|', $params->{$_}]} grep {/members/} keys %$params];
		    my $emails = [];
		    for my $member (@$members) {
			push @$emails, {
			        CN => $member->[0],
				    content => $member->[1],
			} if $member->[1];
		    }
		    $message->{'MEMBER'} = $emails if $#{$emails} >= 0;
		    $message->{'NAME'}->{'VALUE'} = [$params->{NAME}];
		    $message->{'NOTE'}->{'VALUE'} = [$params->{NOTE}] if $params->{NOTE};
		    my $newUID = join ".", map{ join "", map { int rand(9) } 1..$_} (10,1);
		    $newUID .= "@" . $domain;
		    $message->{"UID"}->{"VALUE"} = [$params->{oldMessageID} ? $params->{oldMessageID} : $newUID];

		    my $time = time();
		    my $ximss = getXIMSS($params->{account}, $password);
		    $ximss->send({folderOpen => {
			id => "$time-mailbox",
			folder => $params->{'box'},
			sortField => "To"
				  }});
		    my $mailbox = $ximss->parseResponse("$time-mailbox");
		    if ($mailbox->{'folderReport'}) {
			my $contact = {
			        id => "$time-append",
				folder => $params->{'box'},
				    vCardGroup => $message
			};
			if ($params->{oldUID}) {
			    $contact->{'replacesUID'} = $params->{oldUID};
			    $contact->{'checkOld'} = 'yes';
			}
			$ximss->send({contactAppend => $contact});
			my $append = $ximss->parseResponse("$time-append");
			$Cpanel::CPERROR{'CommuniGate'} = $append->{response}->{errorText} if $append->{response}->{errorText};
		    }
		    $ximss->send({folderClose => {id => "$time-close", folder=>$params->{'box'}}});
		    $ximss->close();
		}
	    }
	}
    }
    return;
}

sub forceArray {
    my $data = shift;
    return undef unless $data;
    if (ref($data) eq "ARRAY") {
	return $data;
    } else {
	return [$data];
    }
}
sub api2_DeleteContactsBox {
    my %OPTS = @_;
    my $account = $OPTS{'account'};
    my $box = $OPTS{'box'};
    my (undef,$dom) = split "@", $account;
    my @domains = Cpanel::Email::listmaildomains();
    my $cli = getCLI();
    my @return;
    for my $domain (@domains) {
	if ($domain eq $dom) {
	    $cli->DeleteMailbox($account, $box);
	}
    }
    my $error_msg = $cli->getErrMessage();
    $Cpanel::CPERROR{'CommuniGate'} = $error_msg unless ($error_msg eq "OK");
    $cli->Logout();
    return 1;
}

sub api2_EditContactsBox {
    my %OPTS = @_;
    my $params = {};
    my $account = $OPTS{'account'};
    my $box = $OPTS{'box'};
    my (undef,$dom) = split "@", $account;
    my @domains = Cpanel::Email::listmaildomains();
    my $cli = getCLI();
    my $return;
    for my $domain (@domains) {
	if ($domain eq $dom) {
	    $return->{acls} = $cli->GetMailboxACL($account, $box);
	}
	my $accounts = $cli->ListAccounts($domain);
	foreach my $userName (sort keys %$accounts) {
	    $return->{accounts}->{"$userName\@$domain"} = 1;
	}
    }
    my $cli = getCLI();
    return $return;
}

sub api2_DoEditContactsBox {
    my %OPTS = @_;
    my $formdump = $OPTS{'formdump'};
    my $params = {};
    for my $row (split "\n", $formdump) {
	if ($row =~ m/^(\S+)\s\=\s(.*?)$/) {
    my $key =$1;
    my $value = $2;
    $params->{$key} = $value;
	}
    }
    if ($params->{save}) {
	my $message = {};
	my (undef,$dom) = split "@", $params->{account};
	my @domains = Cpanel::Email::listmaildomains();
	my $cli = getCLI();
	my $locale = Cpanel::Locale->get_handle();
	for my $domain (@domains) {
	    if ($domain eq $dom) {
		my $resetAcls = {};
		$cli->CreateMailbox($params->{account}, $params->{'box'}, undef, 'IPF.Contact') unless keys %{$cli->ListMailboxes(accountName => $params->{account}, filter => $params->{box})};
		my $oldacls = $cli->GetMailboxACL($params->{account}, $params->{box});
		for my $ac (keys %$oldacls) {
		    $resetAcls->{$ac} = "-" . $oldacls->{$ac};
		}
		$cli->SetMailboxACL($params->{account}, $params->{box}, $resetAcls);
		my $acls = {};
		for (my $i = 0; $i < $params->{boxaclcount}; $i++) {
		    if ($params->{"acl-$i"} && $params->{"aclto-$i"}) {
			my $acl = join "", map {$params->{$_}} grep {$_ =~ m/acl\-$i/} sort keys %$params;
			$acls->{$params->{"aclto-$i"}} = $acl;
		    }
		}
		$cli->SetMailboxACL($params->{account}, $params->{box}, $acls);
		my $error_msg = $cli->getErrMessage();
		$Cpanel::CPERROR{'CommuniGate'} = $error_msg unless ($error_msg eq "OK");
	    }
	}
    }
    my $cli = getCLI();
    return 1;
}

sub api2_exportContacts {
    my %OPTS = @_;
    my $account = $OPTS{'account'};
    my (undef,$dom) = split "@", $account;
    my @domains = Cpanel::Email::listmaildomains();
    my $cli = getCLI();
    my $locale = Cpanel::Locale->get_handle();
    my $return = [];
    for my $domain (@domains) {
	if ($domain eq $dom) {
	    $password = $cli->GetAccountPlainPassword($account);
	    if ($password) {
		my $ximss = getXIMSS($account, $password);
		my $time = time();
		$ximss->send({folderOpen => {
		        id => "$time-mailbox",
			folder => $OPTS{'box'},
			    sortField => "To"
			      }});
		my $mailbox = $ximss->parseResponse("$time-mailbox");
		if ($mailbox->{'folderReport'}) {
		        $ximss->send(
			    {
				folderBrowse => {
				    id => "$time-messages",
				    folder => $OPTS{'box'},
				    index => {
					    from => 0,
					    till => ($mailbox->{'folderReport'}->{'messages'})
				    }
				}
			    });
			my $messages = $ximss->parseResponse("$time-messages");
			for my $message (@{forceArray($messages->{'folderReport'})}) {
			    next if $OPTS{'uid'} && $OPTS{'uid'} != $message->{"UID"};
			    if ($messages->{'folderReport'}) {
				$ximss->send({folderRead => {
				    id => "$time-contact-" . $message->{"UID"},
				    folder => $OPTS{'box'},
				    UID => $message->{"UID"},
				    totalSizeLimit => 5000
					      }});
				my $contact = $ximss->parseResponse("$time-contact-" . $message->{"UID"});
				if ($contact->{'folderMessage'} && $contact->{folderMessage}->{EMail}->{MIME}->{vCard}) {
				    push @$return , {
					vcard => $contact->{folderMessage}->{EMail}->{MIME}->{vCard},
				    };
				}
			    }
			}
		}
		$ximss->send({folderClose => {id => "$time-close", folder=>$OPTS{'box'}}});
		$ximss->close();
	    }
	    last;
	}
    }
    $cli->Logout();
    return $return;
}

sub api2_UploadFile {
    local $Cpanel::IxHash::Modify = 'none';
  FILE:
    foreach my $file ( keys %Cpanel::FORM ) {
        next FILE if $file =~ m/^file-(.*)-key$/;
        next FILE if $file !~ m/^file-(.*)/;
	$Cpanel::CPVAR{"filename"} = $file;
	$Cpanel::CPVAR{"filename"} =~ s/^file-//;
	$Cpanel::CPVAR{"filepath"} = $Cpanel::FORM{$file};
        last;
    }
    return 1;
}

sub api2_ImportContacts {
    my %OPTS = @_;
    my @domains = Cpanel::Email::listmaildomains();
    my $account = $OPTS{'account'};
    my (undef,$domain) = split "@", $account;
    my $cli = getCLI();
    my $result;
    foreach my $dom (@domains) {
	if ($dom eq $domain) {
	    if ($Cpanel::CPVAR{"filepath"} && $Cpanel::CPVAR{"filename"} =~ m/\.vcf$/i && $OPTS{'box'}) {
		open(FI, "<", $Cpanel::CPVAR{"filepath"});
		my $data = [];
		my $contact = [];
		my $rowdata = {};
		my $encoded = undef;
		for my $row (<FI>) {
		    $row =~ s/(\n|\r)//g;
		    $row =~ s/(\n|\r)//g;
		    if ($row =~ m/^(\w+);?(\w+)?.*?\:(.*?)$/) {
			$rowdata = {name => $1, value => $3};
			next if $rowdata->{name} eq 'BEGIN' || $rowdata->{name} eq 'VERSION';
			$rowdata->{type} = $2 if $2 && $2 ne "CHARSER" && $2 ne "ENCODING";
			if ($row =~ s/;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE//i) {
			    $encoded = "qp";
			    next if $rowdata->{value} =~ s/=$//;
			} else {
			    $encoded = undef;
			}
		    } else {
			$rowdata->{value} .= $row;
		    }
		    next if $rowdata->{name} eq 'PHOTO';
		    if ($encoded) {
			$rowdata->{value} = decode_qp($rowdata->{value});
		    }
		    if ($rowdata->{name} eq 'END') {
			push @$data, $contact;
			$contact = [];
		    }
		    push @$contact, $rowdata unless $rowdata->{name} eq "END";
		}
		close FI;
		for my $unit (@$data) {
		    my $message = {};
		    $message->{"UID"}->{"VALUE"} = [join ".", map{ join "", map { int rand(9) } 1..$_} (10,1)];
		    for my $row (@$unit) {
			if ($row->{'name'} eq 'FN') {
			    $message->{"X-FILE-AS"} = [$row->{'value'}];
			    $message->{"FN"} = [$row->{'value'}];
			} elsif ($row->{'name'} eq 'N') {
 			    my @vals = split ';', $row->{'value'};
			    $message->{"N"}->{"GIVEN"} = [$vals[1]] if $vals[1];
			    $message->{"N"}->{"MIDDLE"} = [$vals[2]] if $vals[2];
			    $message->{"N"}->{"FAMILY"} = [$vals[0]] if $vals[0];
			} elsif ($row->{'name'} eq 'ORG') {
 			    my @vals = split ';', $row->{'value'};
			    $message->{"ORG"}->{"ORGNAME"} = [$vals[0]] if $vals[0];
			    $message->{"ORG"}->{"ORGUNIT"} = [$vals[2]] if $vals[2];
			} elsif ($row->{'name'} eq 'TITLE') {
			    $message->{"TITLE"}->{"VALUE"} = [$row->{'value'}];
			} elsif ($row->{'name'} eq 'BDAY') {
			    $message->{"BDAY"}->{"VALUE"} = [$row->{'value'}];
			} elsif ($row->{'name'} eq 'NICKNAME') {
			    $message->{"NICKNAME"}->{"VALUE"} = [$row->{'value'}];
			} elsif ($row->{'name'} eq 'ROLE') {
			    $message->{"ROLE"}->{"VALUE"} = [$row->{'value'}];
			} elsif ($row->{'name'} eq 'TZ') {
			    $message->{"TZ"}->{"VALUE"} = [$row->{'value'}];
			} elsif ($row->{'name'} eq 'GEO') {
			    $message->{"GEO"}->{"VALUE"} = [$row->{'value'}];
			} elsif ($row->{'name'} eq 'NOTE') {
			    $message->{"NOTE"}->{"VALUE"} = [$row->{'value'}];
			} elsif ($row->{'name'} eq 'EMAIL') {
			    $message->{"EMAIL"} = [] unless $message->{"EMAIL"};
			    push @{$message->{"EMAIL"}}, {
				VALUE => [$row->{'value'}],
				USERID => [$row->{'value'}],
				($row->{'type'} || 'OTHER') => {},
			    };
			} elsif ($row->{'name'} eq 'TEL') {
			    $message->{"TEL"} = [] unless $message->{"TEL"};
			    push @{$message->{"TEL"}}, {
				VALUE => [$row->{'value'}],
				NUMBER => [$row->{'value'}],
				($row->{'type'} || 'OTHER') => {},
			    };
			} elsif ($row->{'name'} eq 'ADR') {
 			    my @vals = split ';', $row->{'value'};
			    $message->{"ADR"} = [] unless $message->{"ADR"};
			    my $address = {
				($row->{'type'} || 'OTHER') => {},
			    };
			    $address->{POBOX} = [$vals[0]] if $vals[0];
			    $address->{STREET} = [$vals[2]] if $vals[2];
			    $address->{LOCALITY} = [$vals[3]] if $vals[3];
			    $address->{REGION} = [$vals[4]] if $vals[4];
			    $address->{PCODE} = [$vals[5]] if $vals[5];
			    $address->{CTRY} = [$vals[6]] if $vals[6];
			    push @{$message->{"ADR"}}, $address;
			} elsif ($row->{'name'} eq 'URL') {
			    $message->{"URL"} = [] unless $message->{"URL"};
			    push @{$message->{"URL"}}, {
				VALUE => [$row->{'value'}],
				($row->{'type'} || 'OTHER') => {},
			    };
			}
		    }
		    # Insert the contact;
		    my $time = time();
		    $password = $cli->GetAccountPlainPassword($account);
		    if ($password) {
			my $ximss = getXIMSS($account, $password);
			$ximss->send({folderOpen => {
			    id => "$time-mailbox",
			    folder => $OPTS{'box'},
			    sortField => "To"
				      }});
			my $mailbox = $ximss->parseResponse("$time-mailbox");
			$Cpanel::CPERROR{'CommuniGate'} = $mailbox->{response}->{errorText} if $mailbox->{response}->{errorText};
			if ($mailbox->{'folderReport'}) {
			    my $contact = {
			        id => "$time-append",
				folder => $OPTS{'box'},
				vCard => $message
			    };
			    $ximss->send({contactAppend => $contact});
			    my $append = $ximss->parseResponse("$time-append");
			    $Cpanel::CPERROR{'CommuniGate'} = $append->{response}->{errorText} if $append->{response}->{errorText};
			}
			$ximss->close();
		    }
		}
	    } elsif ($Cpanel::CPVAR{"filepath"} && $Cpanel::CPVAR{"filename"} =~ m/\.csv$/i && $OPTS{'box'}) {
		my $rows = [];
		system '/usr/local/cpanel/bin/csvprocess', $Cpanel::CPVAR{"filepath"}, ( $OPTS{'header'} ? 1 : 0 ), ',';
		my $importdata = Storable::lock_retrieve( $Cpanel::CPVAR{"filepath"}  . '.parsed' );
		for my $row (@{$importdata->{data}}) {
		    my $message = {};
		    $message->{"UID"}->{"VALUE"} = [join ".", map{ join "", map { int rand(9) } 1..$_} (10,1)];
		    $message->{"N"}->{"GIVEN"} = [$row->[0]] if $row->[0];
 		    $message->{"N"}->{"MIDDLE"} = [$row->[1]] if $row->[1];
 		    $message->{"N"}->{"FAMILY"} = [$row->[2]] if $row->[2];
		    $message->{"NICKNAME"}->{"VALUE"} = [$row->[3]] if $row->[3];
		    $message->{"X-FILE-AS"} = [join(" ", grep(/.+/, ($row->[2], $row->[0], $row->[1]) ) )];
		    $message->{"FN"} = [join(" ", grep(/.+/, ($row->[2], $row->[0], $row->[1]) ) )];
		    if ($row->[4] || $row->[5] || $row->[6]) {
			my @home = map {{VALUE => [$_], USERID => [$_], HOME => {}}} split ",", $row->[4];
			my @work = map {{VALUE => [$_], USERID => [$_], WORK => {}}} split ",", $row->[5];
 			my @other = map {{VALUE => [$_], USERID => [$_], OTHER => {}}} split ",", $row->[6];
			$message->{"EMAIL"} = [(@home, @work, @other)];
		    }
		    if ($row->[7] || $row->[8] || $row->[9] || $row->[10] || $row->[11] || $row->[12]) {
			my @home = map {{VALUE => [$_], NUMBER => [$_], HOME => {}}} split ",", $row->[7];
			my @work = map {{VALUE => [$_], NUMBER => [$_], WORK => {}}} split ",", $row->[8];
			my @cell = map {{VALUE => [$_], NUMBER => [$_], CELL => {}}} split ",", $row->[9];
			my @fax = map {{VALUE => [$_], NUMBER => [$_], FAX => {}}} split ",", $row->[10];
			my @video = map {{VALUE => [$_], NUMBER => [$_], VIDEO => {}}} split ",", $row->[11];
 			my @other = map {{VALUE => [$_], NUMBER => [$_], OTHER => {}}} split ",", $row->[12];
			$message->{"TEL"} = [(@home, @work, @cell, @fax, @video, @other)];
		    }
		    if ($row->[13] || $row->[14] || $row->[15] || $row->[16] || $row->[17] || $row->[18] || $row->[19] || $row->[20] || $row->[21] || $row->[22] || $row->[23] || $row->[24] || $row->[25] || $row->[26] || $row->[27] || $row->[28] || $row->[29] || $row->[30]) {
			$message->{"ADR"} = [];
			if ($row->[13] || $row->[14] || $row->[15] || $row->[16] || $row->[17] || $row->[18]) {
			    my $address = {
			    	HOME => {},
			    };
			        $address->{POBOX} = [$row->[13]] if $row->[13];
			        $address->{CTRY} = [$row->[14]] if $row->[14];
			        $address->{STREET} = [$row->[15]] if $row->[15];
			        $address->{LOCALITY} = [$row->[16]] if $row->[16];
			        $address->{REGION} = [$row->[17]] if $row->[17];
			        $address->{PCODE} = [$row->[18]] if $row->[18];
			        push @{$message->{"ADR"}}, $address;
			}
			if ($row->[19] || $row->[20] || $row->[21] || $row->[22] || $row->[23] || $row->[24]) {
			    my $address = {
			    	WORK => {},
			    };
			        $address->{POBOX} = [$row->[19]] if $row->[19];
			        $address->{CTRY} = [$row->[20]] if $row->[20];
			        $address->{STREET} = [$row->[21]] if $row->[21];
			        $address->{LOCALITY} = [$row->[22]] if $row->[22];
			        $address->{REGION} = [$row->[23]] if $row->[23];
			        $address->{PCODE} = [$row->[24]] if $row->[24];
			        push @{$message->{"ADR"}}, $address;
			}
			if ($row->[25] || $row->[26] || $row->[27] || $row->[28] || $row->[29] || $row->[30]) {
			    my $address = {
			    	OTHER => {},
			    };
			        $address->{POBOX} = [$row->[25]] if $row->[25];
			        $address->{CTRY} = [$row->[26]] if $row->[26];
			        $address->{STREET} = [$row->[27]] if $row->[27];
			        $address->{LOCALITY} = [$row->[28]] if $row->[28];
			        $address->{REGION} = [$row->[29]] if $row->[29];
			        $address->{PCODE} = [$row->[30]] if $row->[30];
			        push @{$message->{"ADR"}}, $address;
			}
		    }
		    $message->{"ORG"}->{"ORGNAME"} = [$row->[31]] if $row->[31];
		    $message->{"ORG"}->{"ORGUNIT"} = [$row->[32]] if $row->[32];
		    $message->{"TITLE"}->{"VALUE"} = [$row->[33]] if $row->[33];
		    $message->{"BDAY"}->{"VALUE"} = [$row->[34]] if $row->[34];
		    if ($row->[35] || $row->[36] || $row->[37]) {
			my @home = map {{VALUE => [$_], HOME => {}}} split ",", $row->[35];
			my @work = map {{VALUE => [$_], WORK => {}}} split ",", $row->[36];
 			my @other = map {{VALUE => [$_], OTHER => {}}} split ",", $row->[37];
			$message->{"URL"} = [(@home, @work, @other)];
		    }
		    $message->{"ROLE"}->{"VALUE"} = [$row->[38]] if $row->[38];
		    $message->{"TZ"}->{"VALUE"} = [$row->[39]] if $row->[39];
		    $message->{"GEO"}->{"VALUE"} = [$row->[40]] if $row->[40];
		    $message->{"NOTE"}->{"VALUE"} = [$row->[41]] if $row->[41];
		    # Insert the contact;
		    my $time = time();
		    $password = $cli->GetAccountPlainPassword($account);
		    if ($password) {
		    	my $ximss = getXIMSS($account, $password);
		    	$ximss->send({folderOpen => {
		    	    id => "$time-mailbox",
		    	    folder => $OPTS{'box'},
		    	    sortField => "To"
		    		      }});
		    	my $mailbox = $ximss->parseResponse("$time-mailbox");
		    	$Cpanel::CPERROR{'CommuniGate'} = $mailbox->{response}->{errorText} if $mailbox->{response}->{errorText};
		    	if ($mailbox->{'folderReport'}) {
		    	    my $contact = {
		    	        id => "$time-append",
		    		folder => $OPTS{'box'},
		    		vCard => $message
		    	    };
		    	    $ximss->send({contactAppend => $contact});
		    	    my $append = $ximss->parseResponse("$time-append");
		    	    $Cpanel::CPERROR{'CommuniGate'} = $append->{response}->{errorText} if $append->{response}->{errorText};
		    	}
		    	$ximss->close();
		    }
		}
		unlink $Cpanel::CPVAR{"filepath"}  . '.parsed';

	    } else {
		$Cpanel::CPERROR{'CommuniGate'} = "Error!";
	    }
	    last;
	}
    }
    unlink $Cpanel::CPVAR{"filepath"};
    $cli->Logout();
    return $result;
}

sub api2_ListXmppHistory {
    my %OPTS = @_;
    my @domains = Cpanel::Email::listmaildomains();
    my $account = $OPTS{'account'};
    my (undef,$domain) = split "@", $account;
    my $cli = getCLI();
    my $result;
    foreach my $dom (@domains) {
	if ($dom eq $domain) {
	    $result->{'files'} = $cli->ListStorageFiles($account, 'private/IM');
	    $result->{'account'} = $account;
	    last;
	}
    }
    $cli->Logout();
    return $result;
}

sub api2_GetFile {
    my %OPTS = @_;
    my @domains = Cpanel::Email::listmaildomains();
    my $account = $OPTS{'account'};
    my (undef,$domain) = split "@", $account;
    my $cli = getCLI();
    my $result;
    foreach my $dom (@domains) {
	if ($dom eq $domain) {
	    $result = $cli->ReadStorageFile($account, 'private/IM/' . $OPTS{'file'});
	    last;
	}
    }
    $cli->Logout();
    return $result;
}

sub IsGroupInternal {
  	my $groupwithdomain = shift;
	my @values = split("@",$groupwithdomain);
  	my $domain = @values[1]; 
  	my $group = @values[0]; 
	my $cli = getCLI();
	my $ExistingRules=$cli->GetServerRules() || die "Error: ".$cli->getErrMessage.", quitting";
        my $sa_rulname = $group."_posting_policy";
        foreach my $Rule (@$ExistingRules) {
		if ($Rule->[1] eq "$sa_rulname") {$cli->Logout();return(1);}
        }
	$cli->Logout();
	return(0);
}


sub GroupMembersForRule{
	my $group = shift;
	my $domain = shift;
	my $cli = getCLI();

	my $result;
        my $Settings;
        $Settings=$cli->GetGroup("$group\@$domain");
        foreach (keys %$Settings) {
                my $data=@$Settings{$_};
                if (ref ($data) eq 'ARRAY') {
                        foreach my $member (@$data) {
					if (!$result) {$result = $member; }		
					else {$result .= ",".$member;}
                        }
                }
        }       
	$cli->Logout();
        return $result;
}

sub SetGroupInternal {
        my $groupwithdomain = shift;
        my @values = split("@",$groupwithdomain);
        my $domain = @values[1];
        my $group = @values[0];
	my $cli = getCLI();
 	my @NewRules;
        @NewRules=(); 
        my $ExistingRules=$cli->GetServerRules() || die "Error: ".$cli->getErrMessage.", quitting";
        my $sa_rulname = $group."_posting_policy";
	my $rule_string = GroupMembersForRule($group,$domain);
        my $NewRule =       
                [ 5, $sa_rulname ,
                        [
                                ['Any To or Cc', 'is', $group."@".$domain],
                                ['From', 'not in', $rule_string ]
                        ],
                        [
                                ['Reject with', 'Not Allowed'],
                                ['Discard']
                        ]
                ];
        push(@NewRules,$NewRule);
        foreach my $Rule (@$ExistingRules) {
                push(@NewRules,$Rule);
        }
        $cli->SetServerRules(\@NewRules) || die "Error: ".$cli->getErrMessage.", quitting";
        $cli->Logout();
}

sub SetGroupExternal{
        my $groupwithdomain = shift;
        my @values = split("@",$groupwithdomain);
        my $domain = @values[1];
        my $group = @values[0];
	my $cli = getCLI();
        my @NewRules;
        @NewRules=();
        my $ExistingRules=$cli->GetServerRules() || die "Error: ".$cli->getErrMessage.", quitting";
        my $sa_rulname = $group."_posting_policy";
        foreach my $Rule (@$ExistingRules) {
 		if (!($Rule->[1] eq "$sa_rulname")) {
                	push(@NewRules,$Rule);
		}
        }
        $cli->SetServerRules(\@NewRules) || die "Error: ".$cli->getErrMessage.", quitting";
        $cli->Logout();
}


sub api2 {
    my $func = shift;
    my (%API);
    $API{'GWAccounts'} = {};
    $API{'EnableGW'} = {};
    $API{'DisableGW'} = {};
    $API{'provisioniPhone'} = {};
    $API{'listpopswithdisk'} = {};
    $API{'addalias'} = {};
    $API{'delalias'} = {};
    $API{'listalias'} = {};
    $API{'addforward'} = {};
    $API{'delforward'} = {};
    $API{'listforwards'} = {};
    $API{'ListDefAddress'} = {};
    $API{'SetDefAddress'} = {};
    $API{'SpamAssassinStatus'} = {};
    $API{'EnableSpamAssassin'} = {};
    $API{'DisableSpamAssassin'} = {};
    $API{'SpamAssassinStatusAutoDelete'} = {};
    $API{'EnableSpamAssassinAutoDelete'} = {};
    $API{'DisableSpamAssassinAutoDelete'} = {};
    $API{'SpamAssassinStatusSpamBox'} = {};
    $API{'EnableSpamAssassinSpamBox'} = {};
    $API{'DisableSpamAssassinSpamBox'} = {};
    $API{'AddMailingList'} = {};
    $API{'ListMailingLists'} = {};
    $API{'DelMailingList'} = {};
    $API{'RenameMailingList '} = {};
    $API{'GetListSetting'} = {};
    $API{'PrintTextArea'} = {};
    $API{'ListMailingListsSubs'} = {};
    $API{'SetSubSettings'} = {};
    $API{'UnSub'} = {};
    $API{'Sub'} = {};
    $API{'ListGroups'} = {};
    $API{'DelGroup'} = {};
    $API{'RenameGroup'} = {};
    $API{'AddGroup'} = {};
    $API{'ListGroupMembers'} = {};
    $API{'AddGroupMember'} = {};
    $API{'RemoveGroupMember'} = {};
    $API{'GetGroupSettings'} = {};
    $API{'SetGroupSettings'} = {};
    $API{'SetAutoresponder'} = {};
    $API{'ListAutoresponder'} = {};
    $API{'DeleteAutoresponder'} = {};
    $API{'ListForwardersBackups'} = {};
    $API{'UploadForwarders'} = {};
    $API{'RestoreForwarders'} = {};
    $API{'ListAccountsBackups'} = {};
    $API{'GetAccountsBackups'} = {};
    $API{'UninstallSRVXMPP'} = {};
    $API{'InstallSRVXMPP'} = {};
    $API{'UninstallSRVSIP'} = {};
    $API{'InstallSRVSIP'} = {};
    $API{'UninstallSRVCALDAV'} = {};
    $API{'InstallSRVCALDAV'} = {};
    $API{'UninstallSRVCARDDAV'} = {};
    $API{'InstallSRVCARDDAV'} = {};
    $API{'GetSRV'} = {};
    return ( \%{ $API{$func} } );
}

1;
