#!/usr/bin/perl

package DownloadManager;

use POSIX ":sys_wait_h";

sub new {
	my $class = shift;
	# Configuración por defecto
	my $self = {
		# Debug off
		debug => 0,
		# Opciones de wget
		options => "-nv --user-agent=\"Mozilla/5.0 \(X11; Linux x86_64\) AppleWebKit/537.36 \(KHTML, like Gecko\) Chrome/37.0.2062.120 Safari/537.36\" --header=\"Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\" --header=\"Accept-Language: es-ES,es;q=0.8,en-US;q=0.5,en;q=0.3\" --header=\"Accept-Encoding: gzip, deflate\" --header=\"Accept-Charset: ISO-8859-1,utf-8;q=0.7,*;q=0.7\"",
		# Autocancelable, mínimo kbps para dar fallo
		autocancelable_rate => 100,
		# Autocancelable, máximo de fallos admisibles
		autocancelable_maxfails => 3,
		# Autocancelable, tiempo entre comprobación de ratios
		autocancelable_time => 10
	};

	return bless $self, $class;
}

sub _log {
	print shift;
}

sub _basic_download {
	my $self = shift;
	my($cancelable, $url, $output, $extraOptions) = @_;
	my $command = "wget $self->{options} $extraOptions -O \"$output\" \"$url\"";
	if ($self->{debug}) {
		&_log("$command\n");
	} else {
		if ($cancelable) {
			my $pid = fork();
			die "unable to fork: $!" unless defined($pid);
			if (!$pid) {  # child
				exec($command);
				exit;
			}
			&_wait_download($self, $output, $pid)
		} else {
			system($command);
		}
	}
}

sub _is_child_alive {
	my $pid = shift;
	my $res = waitpid($pid, WNOHANG);
	return $res == 0;
}

sub _wait_download {
	($self, $filename, $pid) = @_;
	my ($lastsize, $size, $rate, $fails) = (0,0,0,0);
	do {
		sleep $self->{autocancelable_time};
		$lastsize = $size;
		$size = `ls -l \"$filename\" | cut -d\" \" -f5`;
		chomp $size;
		$rate = int( ($size - $lastsize) / $self->{autocancelable_time} / 1024 );
		$fails += 1 if ($rate < $self->{autocancelable_rate});
		$fails -= 1 if ($fails > 0 && $rate > 2*$self->{autocancelable_rate});
		&_log("\n\tActual rate = $rate -> Fails:$fails -> $filename\n");
	} while (&_is_child_alive($pid) && $fails <= $self->{autocancelable_maxfails});

	&_log("kill -9 $pid +1\n");
	kill "SIGKILL", $pid;
	kill "SIGKILL", ($pid+1);
	system("kill -9 $pid");
	system("kill -9 ". ($pid+1));
}

sub download {
	my($self, $url, $output, $extra_options) = @_;
	&_basic_download($self, 0, $url, $output, $extra_options);
}

sub download_cancelable {
	my($self, $url, $output, $extra_options) = @_;
	&_basic_download($self, 1, $url, $output, $extra_options);
}

sub enable_debug {
	my $self = shift;
	$self->{debug} = 1;
}

sub disable_debug {
	my $self = shift;
	$self->{debug} = 0;
}

sub config_autocancelable {
	my ($self, $rate, $maxfails, $time) = @_;
	$self->{autocancelable_rate} = $rate;
	$self->{autocancelable_maxfails} = $maxfails;
	$self->{autocancelable_time} = $time;
}	

# TODO download post

1
