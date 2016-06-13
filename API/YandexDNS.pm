#!/usr/bin/env perl
package API::YandexDNS;

use warnings;
use strict;

use lib::abs qw{../};
use Log qw{_print_it};

use JSON::XS qw{decode_json};

use HTTP::Request;
use HTTP::Status qw{:is};
use LWP::UserAgent;


our $api_dns_url_prefix = 'https://pddimp.yandex.ru/api2/admin/dns/';


sub _get_api_response {
	my ( $action, $params ) = @_;

	unless ($action) {
		_print_it('missing URL variable', 'error');
		return undef;
	}

	unless ( $params && keys %$params ) {
		_print_it('missing params', 'error');
		return undef;
	}

	my $token = delete $params->{'token'};
	unless ($token) {
		_print_it('token must be defined', 'error');
		return undef;
	}

	my $r;
	my $ua = LWP::UserAgent->new( (timeout => 5) );
	if ($action eq 'list') {
		my $request_url = $api_dns_url_prefix . $action . '?' .
			join('&', map { "$_=$params->{$_}" } keys %$params);
		$r = $ua->get(
			$request_url,
			'PddToken'	=> $token,
		);
	} elsif (
		$action eq 'add' or
		$action eq 'del' or
		$action eq 'edit'
	) {
		$r = $ua->post(
			$api_dns_url_prefix . $action,
			'PddToken'	=> $token,
			'Content'	=> $params,
		);
	} else {
		_print_it('action might be: "list", "add", "del" or "edit"', 'error');
		return undef;
	}

	if ($r->is_success) {
		my $h_parse_json;
		eval { $h_parse_json = decode_json($r->content) };
		if ($@) {
			_print_it('error while parse JSON: ' . $@);
			return undef;
		}

		unless ($h_parse_json) {
			_print_it('empty JSON answer');
			return undef;
		}

		return $h_parse_json;
	}

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
	$h_bless->{'cache_flag'} = delete $api_options->{'cache'}
		if (exists $api_options->{'cache'});
	$h_bless->{'domain_name'} = $domain_name if ($domain_name);
	$h_bless->{'api_options'} = $api_options if ($api_options and ref($api_options) eq 'HASH');

	bless $h_bless, $class;
	return $h_bless;
}


sub _cache {
	my $self = shift;
	my ($domain_name, $cache_data) = @_;

	unless ($domain_name) {
		_print_it('cache use only for show domain list, domain must be defined');
		return undef;
	}

	# check flag 'cache' and if 'true', than store data or read from cache
	if (
		exists $self->{'cache_flag'} &&
		$self->{'cache_flag'} =~ m{(y(es)?|true|1)}io
	) {
		if ($cache_data) {
			$self->{'cache_data'}->{$domain_name} = $cache_data;
			return 1;
		}

		return $self->{'cache_data'}->{$domain_name}
			if (exists $self->{'cache_data'}->{$domain_name});
	}

	return 0;
}


sub _get_domain_records {
	my $self = shift;

	my ($domain_name) = @_;
	$domain_name ||= $self->{'domain_name'};

	unless ($domain_name) {
		_print_it('domain name must be defined');
		return undef;
	}

	my $cache = $self->_cache($domain_name);
	return $cache if ($cache);

	my $json_answer = _get_api_response('list',
		{
			'domain' => $domain_name,
			'token' => $self->{'token'},
		}
	);

	unless ($json_answer) {
		_print_it('cannot get record for domain ' . $domain_name);
		return undef;
	}

	$self->_cache($domain_name, $json_answer);
	return $json_answer;
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
		my $h_json_domain = $self->_get_domain_records( join('.', @prefixes) );
		if (
			$h_json_domain &&
			exists $h_json_domain->{'success'} &&
			$h_json_domain->{'success'} eq 'ok'
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
	if ( !$h_find_nearest_domain || exists $h_find_nearest_domain->{'error'} ) {
		_print_it('cannot get domain data');
		return undef;
	}

	my ($h_json_domain, $h_valid_id_records, $valid_domain_name) = (
		$self->_get_domain_records($h_find_nearest_domain->{'domain'}),
		undef,
		$h_find_nearest_domain->{'domain'}
	);

	if ( exists $h_json_domain->{'records'} and scalar(@{$h_json_domain->{'records'}}) ) {
		for my $record_data ( @{$h_json_domain->{'records'}} ) {
			if (
				exists $record_data->{'fqdn'} &&
				exists $record_data->{'record_id'} &&
				$record_data->{'fqdn'} eq $domain_name
			) {
				$h_valid_id_records->{ $record_data->{'record_id'} } = $record_data;
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
		_print_it('cannot found nearest domain');
		return undef;
	}

	my $params = $self->{'api_options'};
	$params->{'token'} = $self->{'token'};
	$params->{'domain'} = $h_find_nearest_domain->{'domain'};
	$params->{'subdomain'} = $h_find_nearest_domain->{'subdomain'} if ( exists $h_find_nearest_domain->{'subdomain'} );
	$params->{'type'} = uc($type);

	if ( ref(\$content) eq 'SCALAR' ) {
		$params->{'content'} = $content;
	} elsif ( ref($content) eq 'HASH' ) {
		map { $params->{$_} = $content->{$_} } keys %{$content};
	} else {
		_print_it('content must be scalar or hash');
		return undef;
	}

	my $json_answer;
	if ($record_id) {
		$params->{'record_id'} = $record_id;
		$json_answer = _get_api_response('edit', $params);
	} else {
		$json_answer = _get_api_response('add', $params);
	}

	if ( !$json_answer || exists $json_answer->{'error'} ) {
		_print_it('cannot add/update record');
		return undef;
	}

	return 1 if ($json_answer->{'success'} eq 'ok');
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
		for my $tmp_record_id (keys %$h_records_id) {
			if (
				($type && lc($h_records_id->{$tmp_record_id}->{'type'}) eq lc($type) ) ||
				!defined $type
			) {
				my $json_answer = _get_api_response(
					'del',
					{
						'token' => $self->{'token'},
						'domain' => $h_records_id->{$tmp_record_id}->{'domain'},
						'record_id' => $tmp_record_id
					}
				);

				if ( !$json_answer || exists $json_answer->{'error'} ) {
					_print_it('cannot del record');
					return undef;
				}
			}
		}
	}

	return 1;
}


1;
