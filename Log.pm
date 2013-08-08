#!usr/bin/env perl
package Log;

use warnings;
use strict;

use POSIX qw{strftime};


our @ISA	= qw{Exporter};
our @EXPORT_OK	= qw{
	_print_it
};


sub _print_it {
	my ($msg, $type) = @_;
	$type ||= 'error';

	my @caller_args = ();
	for (my $i = 0 ; $i < 5 ; $i++) {
		my ($package, $filename, $line) = (caller($i))[0..2];
		last unless ($package && $filename && $line);

		$package = $filename if $package eq "main";
		push(@caller_args, "$package:$line")
	}

	my $output = strftime("%Y/%m/%d %H:%M:%S %z", localtime) . " [$type] " .
	( $msg ?
	$msg :
	'undefined msg variable'
	) .
	( (scalar(@caller_args) > 0 ) ?
	' (' . join(' < ', @caller_args) . ')' :
	''
	) . "\n";

	( $type eq "error" ) ? ( print STDERR $output ) : ( print STDOUT $output ) ;
	return 1;
}


1;
