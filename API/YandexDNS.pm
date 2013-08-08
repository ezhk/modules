#!/usr/bin/env perl
package API::YandexDNS;

use warnings;
use strict;

use lib::abs qw{../};
use Log qw{_print_it};

use XML::Simple qw{XMLin};

use HTTP::Request;
use HTTP::Status qw{:is};
use LWP::UserAgent;


our $api_dns_url_prefix = 'https://pddimp.yandex.ru/nsapi/';


sub _get_api_response {
	my ( $url, $url_get_params ) = @_;

	unless ($url) {
		_print_it('missing URL variable', 'error');
		return undef;
	}

	unless ( $url_get_params && keys %$url_get_params ) {
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


sub _get_domain_records {
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


sub _find_nearest_subdomain_and_domain {
	my $self = shift;

	my ($domain_name) = @_;
	$domain_name ||= $self->{'domain_name'};

	unless ($domain_name) {
		_print_it('domain name must valid');
		return undef;
	}

	my @subdomain;
	my @prefixes = split(/\./, $domain_name);
	for (my $i = scalar(@prefixes); $i > 0; $i--) {
		my $h_xml_domain = $self->_get_domain_records( join('.', @prefixes) );
		if (
			$h_xml_domain &&
			exists $h_xml_domain->{'domains'}->{'error'} &&
			$h_xml_domain->{'domains'}->{'error'} eq 'ok'
		) {
			last;
		}

		push(@subdomain, shift @prefixes);
	}

	# If not found valid domain name
	unless (scalar(@prefixes)) {
		_print_it('cannot find nearest domain');
		return undef;
	}

	return {
		'subdomain' => join('.', @subdomain),
		'domain' => join('.', @prefixes)
	};
}


sub _check_exists_record {
	my $self = shift;

	my ($domain_name) = @_;
	$domain_name ||= $self->{'domain_name'};

	unless ($domain_name) {
		_print_it('domain name must valid');
		return undef;
	}

	my $h_find_nearest_domain = $self->_find_nearest_subdomain_and_domain($domain_name);
	unless ( $h_find_nearest_domain && exists $h_find_nearest_domain->{'domain'} ) {
		_print_it('cannot get domain data');
		return undef;
	}

	my ($h_xml_domain, $h_valid_id_records, $valid_domain_name) = (
		$self->_get_domain_records($h_find_nearest_domain->{'domain'}),
		undef,
		$h_find_nearest_domain->{'domain'}
	);

	if (exists $h_xml_domain->{'domains'}->{'domain'}) {
		unless (exists $h_xml_domain->{'domains'}->{'domain'}->{'nsdelegated'}) {
			_print_it('domain ' . $valid_domain_name . ' not delegated', 'warning');
		}

		if (exists $h_xml_domain->{'domains'}->{'domain'}->{'response'}->{'record'}) {
			my $h_records = $h_xml_domain->{'domains'}->{'domain'}->{'response'}->{'record'};
			for my $tmp_id_record ( keys %{$h_records} ) {
				next unless (exists $h_records->{$tmp_id_record}->{'domain'});
				next unless ($h_records->{$tmp_id_record}->{'domain'} eq $domain_name );

				$h_valid_id_records->{$tmp_id_record} = $h_records->{$tmp_id_record};
			}
		}
	} else {
		_print_it('non exists domains->domain internal data', 'warning');
	}

	return $h_valid_id_records if ($h_valid_id_records);
	return undef;
}



sub set_record {
	my $self = shift;

	my ($domain_name, $type, $content) = @_;
	$domain_name ||= $self->{'domain_name'};

	unless ($domain_name && $type && $content) {
		_print_it('domain name, type or content must defined');
		return undef;
	}

	if ( $type !~ m{^(?:a|aaaa|cname|mx|ns|srv|txt)$}io ) {
		_print_it("possible record type: A, AAAA, CNAME, MX, NS, SRV, TXT");
		return undef;
	}

	my ($h_records_id, $record_id) = ($self->_check_exists_record($domain_name), undef);

	if ($h_records_id && keys %{$h_records_id}) {
		for my $tmp_record_id (keys %$h_records_id) {
			if ( lc($h_records_id->{$tmp_record_id}->{'type'}) eq lc($type)) {
				$record_id = $tmp_record_id;
				last;
			}
		}
	}

	my $h_find_nearest_domain = $self->_find_nearest_subdomain_and_domain($domain_name);
	unless ( $h_find_nearest_domain && exists $h_find_nearest_domain->{'domain'} ) {
		_print_if('cannot found nearest domain');
		return undef;
	}

	my $get_params = $self->{'api_options'};
	$get_params->{'token'} = $self->{'token'};
	$get_params->{'domain'} = $h_find_nearest_domain->{'domain'};
	$get_params->{'subdomain'} = $h_find_nearest_domain->{'subdomain'} if ( exists $h_find_nearest_domain->{'subdomain'} );

	if ( ref(\$content) eq 'SCALAR' ) {
		$get_params->{'content'} = $content;
	} elsif ( ref($content) eq 'HASH' ) {
		for my $param (keys %{$content}) {
			$get_params->{$param} = $content->{$param};
		}
	} else {
		_print_it('content must be scalar or hash');
		return undef;
	}

	my $xml_answer;
	if ($record_id) {
		$get_params->{'record_id'} = $record_id;
		$xml_answer = _get_api_response(
			$api_dns_url_prefix . 'edit_' . lc($type) . '_record.xml',
			$get_params
		);
	} else {
		$xml_answer = _get_api_response(
			$api_dns_url_prefix . 'add_' . lc($type) . '_record.xml',
			$get_params
		);
	}

	my $h_parse_xml;
	eval { $h_parse_xml = XMLin($xml_answer) };
	if ($@) {
		_print_it('error while parse XML: ' . $@);
		return undef;
	}

	unless ( $h_parse_xml && exists $h_parse_xml->{'domains'}->{'error'} ) {
		_print_it('cannot get request error status');
		return undef;
	}

	return 1 if ($h_parse_xml->{'domains'}->{'error'} eq 'ok');

	_print_it('cannot set records content: ' . $h_parse_xml->{'domains'}->{'error'});
	return 0;
}


sub del_record {
        my $self = shift;

        my ($domain_name, $type) = @_;
	$domain_name ||= $self->{'domain_name'};

	unless ($domain_name) {
		_print_it('domain name must defined');
		return undef;
	}

	my $h_records_id = $self->_check_exists_record($domain_name);
	if ( $h_records_id && keys %{$h_records_id} ) {
		my $h_find_nearest_domain = $self->_find_nearest_subdomain_and_domain($domain_name);
		unless ( $h_find_nearest_domain && exists $h_find_nearest_domain->{'domain'} ) {
			_print_if('cannot found nearest domain');
			return undef;
		}

		for my $tmp_record_id (keys %$h_records_id) {
			if (
				($type && lc($h_records_id->{$tmp_record_id}->{'type'}) eq lc($type) ) ||
				!defined $type
			) {
				my $xml_answer = _get_api_response(
					$api_dns_url_prefix . 'delete_record.xml',
					{
						'token' => $self->{'token'},
						'domain' => $h_find_nearest_domain->{'domain'},
						'record_id' => $tmp_record_id
					}
				);

				my $h_parse_xml;
				eval { $h_parse_xml = XMLin($xml_answer) };
				if ($@) {
					_print_it('error while parse XML: ' . $@);
					return undef;
				}

				unless ( $h_parse_xml && exists $h_parse_xml->{'domains'}->{'error'} ) {
					_print_it('cannot get request error status');
					return undef;
				}

				unless ( $h_parse_xml->{'domains'}->{'error'} eq 'ok' ) {
					_print_it('cannot del records content: ' . $h_parse_xml->{'domains'}->{'error'});
					return 0;
				}
			}
		}
	}

	return 1;
}


1;
