#!/usr/bin/env perl
package YandexDNS;

use warnings;
use strict;

use POSIX qw{strftime};

use HTTP::Request;
use HTTP::Status qw{:is};
use LWP::UserAgent;


our $api_dns_url_prefix = 'https://pddimp.yandex.ru/nsapi/';


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


sub _get_api_response {
	my ( $url, $url_get_params ) = @_;

	unless ($url) {
		_print_it('missing URL variable', 'error');
		return undef;
	}

	unless (
		$url_get_params &&
		ref($url_get_params) eq 'HASH' &&
		keys %$url_get_params
	) {
		_print_it('missing GET params', 'error');
		return undef;
	}

	my $request_url = $url . '?' .
		join('&', map { "$_=$url_get_params->{$_}" } keys %$url_get_params);

	my $req = new HTTP::Request;
	$req->url($request_url);
	$req->method('GET');
	$req->header( {"User-Agent" => "Yandex API DNS - ezhk's module"} );

	my $ua = LWP::UserAgent->new( (timeout => 5) );
	my $r = $ua->request($req);

	return $r->content if ( is_success($r->status_line) );
	return undef;
}


1;
