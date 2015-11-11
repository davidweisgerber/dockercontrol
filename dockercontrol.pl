#!/usr/bin/perl -w
 
use JSON;
use Data::Dumper;
use File::Slurp;
use File::Path qw(make_path);

my $jsonText = read_file("config.js") or die "Could not open config file";
my $json = decode_json($jsonText);

my $pipework = $json->{"pipework"};
my $action = $ARGV[0] || "";

if ($action eq "check") {
    print check($ARGV[1])."\n";
} elsif ($action eq "enter") {
    enter($ARGV[1]);
} elsif ($action eq "run") {
    run($ARGV[1]);
} elsif ($action eq "stop") {
    stop($ARGV[1]);
} elsif ($action eq "runall") {
    runall();
} elsif ($action eq "stopall") {
    stopall();
} elsif ($action eq "checkall") {
    checkall();
} else {
    help();
}

sub getByName {
    my $i = 0;
    while(defined($json->{"container"}[$i])) {
        my $containerDef = $json->{"container"}[$i];
        if ($containerDef->{"name"} eq $_[0]) {
            return $containerDef;
        }
        
        $i++;
    }
    
    return undef;
}

sub check {
    my $checkresult = `docker inspect $_[0] 2>&1`;
    if ($checkresult =~ /^Error:/) {
        return "not present";
    }
    
    my $checkJson = decode_json($checkresult);
   
    return $checkJson->[0]->{"State"}->{"Status"};
}

sub enter {
    system("docker exec -it $_[0] /bin/bash");
    print "\n";
}

sub run {
    my $checkresult = check($_[0]);
    
    if ($checkresult eq "not present") {
        start($_[0]);
    } elsif ($checkresult eq "exited") {
        system("docker start $_[0]");
    }
}

sub checkDirectory {
    if (!-e $_[0]) {
        make_path($_[0]);
    }
}

sub start {
    my $config = getByName($_[0]);
    
    if (!defined($config)) {
        print "Configuration for $_[0] not found\n";
        exit 1;
    }
    
    my $startString = "docker run --name $_[0] -d";
    foreach my $key (keys(%{$config->{"ports"}})) {
        $startString .= " -p ".$key.":".$config->{"ports"}->{$key};
    }
    
    foreach my $key (keys(%{$config->{"volumes"}})) {
        checkDirectory($key);
        $startString .= " -v ".$key.":".$config->{"volumes"}->{$key};
    }
    
    $startString .= " ".$config->{"image"};
    
    system($startString);
    
    if (defined($config->{"network-interface"})) {
        my $pipeworkString = $pipework." ".$config->{"network-interface"}." ".$_[0]." ";
        if ($config->{"network-address"} eq "dhcp") {
            $pipeworkString .= "dhclient";
        } else {
            $pipeworkString .= $config->{"network-address"};
        }
        
        system($pipeworkString);
    }
}

sub stop {
    my $check = check($_[0]);
    if ($check eq "running") {
        system("docker stop $_[0]");
    } elsif ($check eq "not present") {
        return;
    }

    system("docker rm $_[0]");
}

sub runall {
    my $i = 0;
    while(defined($json->{"container"}[$i])) {
        my $containerDef = $json->{"container"}[$i];
        run($containerDef->{"name"});
        $i++;
    }
}

sub stopall {
    my $i = 0;
    while(defined($json->{"container"}[$i])) {
        my $containerDef = $json->{"container"}[$i];
        stop($containerDef->{"name"});
        $i++;
    }
}

sub checkall {
    my $i = 0;
    while(defined($json->{"container"}[$i])) {
        my $containerDef = $json->{"container"}[$i];
        print $containerDef->{"name"}." ".check($containerDef->{"name"})."\n";
        $i++;
    }
}

sub help {
    print qq|
Simple docker helper with config file (TM)

Commands:

* check <Container>
Checks whether the container is running or not

* enter <Container>
Opens a bash in the container and lets you control it from this terminal

* run <Container>
Runs the container

* stop <Container>
Stops the container

* runall
Runs all containers

* stopall
Stops all containers

* checkall
Prints the state of all containers
|;    
}
