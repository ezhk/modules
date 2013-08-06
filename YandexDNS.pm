#!/usr/bin/env perl
package YandexDNS;

use warnings;
use strict;

use POSIX qw{strftime};
use XML::Simple qw{XMLin};

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


sub new {
	my $tmp = shift;
	my $class = ref($tmp) || $tmp;

	my ($token, $domain_name, $api_options) = @_;
	unless ($token) {
		_print_it('API token must be defined');
		return undef;
	}

	my $h_bless = { token => $token };
	$h_bless->{'domain_name'} = $domain_name if ($domain_name);
	$h_bless->{'api_options'} = $api_options if ($api_options and ref($api_options) eq 'HASH');

	bless $h_bless, $class;
	return $h_bless;
}


sub get_domain_records {
	my $self = shift;

	my ($domain_name) = @_;
	$domain_name ||= $self->{'domain_name'};

	unless ($domain_name) {
		_print_it('domain name must be defined');
		return undef;
	}

	my $xml_answer = _get_api_response($api_dns_url_prefix . 'get_domain_records.xml',
		{
			'domain' => $domain_name,
			'token' => $self->{'token'},
		}
	);

	unless ($xml_answer) {
		_print_it('cannot get record for domain ' . $domain_name);
		return undef;
	}

	my $h_parse_xml;
	eval { $h_parse_xml = XMLin($xml_answer) };
	if ($@) {
		_print_it('error while parse XML: ' . $@);
		return undef;
	}

	unless ($h_parse_xml) {
		_print_it('empty XML answer');
		return undef;
	}

	return $h_parse_xml;
}


sub set_a_record {
	my $self = shift;

	my ($domain_name, $ipv4_address) = @_;
	$domain_name ||= $self->{'domain_name'};

	unless ($domain_name && $ipv4_address) {
		_print_it('domain name, IPv4 and token addr must valid');
		return undef;
	}

	# Validate IPv4 addr
	my @octets = split(/\./, $ipv4_address);
	if ( scalar(@octets) != 4 ) {
		_print_it('IPv4 must contain 4 octets');
		return undef;
	}
	for my $octet (@octets) {
		if ( $octet !~ m{^\d+$}o || $octet > 255 || $octet < 0 ) {
			_print_it('non valid octet "' . $octet . '" in IPv4 addr ' . $ipv4_address);
			return undef;
		}
	}

	# Check exists record
	# first step - find nearest valid domain name
	my @prefixes = split(/\./, $domain_name);
	for (my $i = scalar(@prefixes); $i > 0; $i--) {
		my $h_xml_domain = $self->get_domain_records( join('.', @prefixes) );
		if (
			$h_xml_domain &&
			exists $h_xml_domain->{'domains'}->{'error'} &&
			$h_xml_domain->{'domains'}->{'error'} eq 'ok'
		) {
			last;
		}

		shift @prefixes;
	}

	# If not found valid domain name
	unless (scalar(@prefixes)) {
		_print_it('cannot get domain data');
		return undef;
	}

	# Valid domain join('.', @prefixes);
	# to be continued
}


1;
