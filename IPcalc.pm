#!usr/bin/env perl
package IPcalc;

# Methods:
# - IPv4 methods:
#   - convert_ipv4_netmask - return ipv4 netmask in format 255.255.254.0
#   - get_min_ipv4_address - return network's address
#   - get_max_ipv4_address - return max network address (broadcast)
# - IPv6 methods:
#   - convert_to_compact_ipv6 - return short view ipv6 addr
#   - convert_to_full_ipv6 - return long view ipv6 addr
#   - get_min_ipv6_address - return min network address in long view format
#   - get_max_ipv6_address - return max network address in long view format

use strict;
use warnings;

use lib::abs qw{./};
use Log qw{_print_it};

use Exporter qw{import};
our @EXPORT_OK  = qw{
	convert_ipv4_netmask
	get_min_ipv4_address
	get_max_ipv4_address
	convert_to_compact_ipv6
	convert_to_full_ipv6
	get_min_ipv6_address
	get_max_ipv6_address
};


# "convert_ipv4_netmask" return netmask in format 255.255.254.0
# Input params:
# - network mask as /23, 0xfffffe00 or binary format
#
# Return >scalar

sub convert_ipv4_netmask {
	my ($netmask) = @_;

	unless ($netmask) {
		_print_it('empty input params');
		return undef;
	}

	# Hex mask
	if ($netmask =~ m:^0x:io) {
		$netmask = join( '.', unpack( 'C4', pack('N', hex($netmask))) );
	}

	# Binary mask
	elsif ($netmask =~ m:[01]{1,8}(\.[01]{1,8}){3}:io) {
		$netmask =~ s:\.::io;
		$netmask = join( '.', unpack('C4', pack ('B32', $netmask)) );
	}

	# Short mask (prefix)
	elsif ($netmask =~ m:^/?(\d+)$:io) {
		$netmask = join( '.', unpack( 'C4', pack('B32', '1' x $1 . '0' x (32 - $1)) ) );
	}

	else {
		my @octets = split(/\./, $netmask);
		unless ( scalar(@octets) == 4 ) {
			_print_it('cannot determine netmask type');
			return undef;
		}

		for my $octet ( @octets ) {
			unless  ( $octet =~ m{^\d+$}o) {
				_print_it('octet value must be numeric');
				return undef;
			}

			if ( $octet < 0 || $octet > 255 ) {
				_print_it('octet value out of range 0..255');
				return undef;
			}
		}
	}

	return $netmask;
}


# "get_min_ipv4_address" return network's address
# 192.168.0.2/255.255.255.0 > 192.168.0.0
# Input parameters:
# - ipv4 address
# - netmask or prefix
#
# Return >scalar

sub get_min_ipv4_address {
	my ($ipaddr, $netmask) = @_;

	unless ( $ipaddr && $netmask ) {
		_print_it('empty input params');
		return undef;
	}

	$netmask = convert_ipv4_netmask($netmask);
	unless ( $netmask ) {
		_print_it("cannot convert netmask '$netmask'");
		return undef;
	}

	my $binary_addr = unpack( 'B32', pack('C4', split(/\./, $ipaddr)) );
	my $binary_mask = unpack( 'B32', pack('C4', split(/\./, $netmask)) );

	return join('.', unpack( 'C4', pack('B32', $binary_addr & $binary_mask) ));
}


# "get_max_ipv4_address" return max network address (broadcast)
# 192.168.0.2/255.255.255.0 > 192.168.0.255
# Input parameters:
# - ipv4 address
# - netmask or prefix
#
# Return >scalar

sub get_max_ipv4_address {
	my ($ipaddr, $netmask) = @_;

	unless ( $ipaddr && $netmask ) {
		_print_it('empty input params');
		return undef;
	}

	$netmask = convert_ipv4_netmask($netmask);
	unless ( $netmask ) {
		_print_it("cannot convert netmask '$netmask'");
		return undef;
	}

	my $binary_addr = unpack( 'B32', pack('C4', split(/\./, $ipaddr)) );
	my $binary_mask = unpack( 'B32', pack('C4', split(/\./, $netmask)) );

	return join('.', unpack( 'C4', pack('B32', ($binary_addr & $binary_mask) | (~$binary_mask)) ));
}


# "convert_to_compact_ipv6" return short ipv6 addr
# a:0000:0000:0000::0:a > a::a
# Input variable:
# - IPv6 address
#
# Return >scalar

sub convert_to_compact_ipv6 {
	my ($ipv6_addr) = @_;

	unless ( $ipv6_addr && $ipv6_addr =~ m{^[0-9a-f:]+$}io ) {
		_print_it('wrong input IPv6 address');
		return undef;
	}
	

	my @quartets = split(/:/, $ipv6_addr);
	if (scalar @quartets > 8) {
		_print_it('too mush quartets');
		return undef;
	}

	my $full_ipv6 = convert_to_full_ipv6($ipv6_addr);
	my @compact_ipv6 = split(/:/, $full_ipv6);

	my $counter = 0;
	my $tmp_hash = {};
	for (my $i = 0 ; $i < scalar @compact_ipv6 ; $i++ ) {
		$compact_ipv6[$i] = $1 if ( $compact_ipv6[$i] =~ m{^0+([0-9a-f]+)$}io );

		# Calculate offset and lenght of zero quatets
		if ( $compact_ipv6[$i] eq '0' ) {
			$tmp_hash->{$i-$counter} += 1;
			$counter++;
		} else {
			$counter = 0;
		}
	}

	foreach my $offset (sort {$tmp_hash->{$b} <=> $tmp_hash->{$a}} keys %$tmp_hash) {
		my $empty_counts = 1;

		# If :: in begin or end, then white two ''
		if ($tmp_hash->{$offset} eq "0" || ($offset + $tmp_hash->{$offset}) >= scalar(@compact_ipv6) ) {
			$empty_counts++;
		}

		splice(@compact_ipv6, $offset, $tmp_hash->{$offset}, ('') x $empty_counts);
		last;
	}

	return lc join(':', @compact_ipv6);
}


# "convert_to_full_ipv6" return long ipv6 addr
# a:b:c:d:e:f::1 > 000a:000b:000c:000d:000f:0000:0000:0001
# Input variable: 
# - IPv6 address
#
# Return >scalar

sub convert_to_full_ipv6 {
	my ($ipv6_addr) = @_;
	unless ( $ipv6_addr && $ipv6_addr =~ m{^[0-9a-f:]+$}io ) {
		_print_it('wrong input IPv6 address');
		return undef;
	}

	my $shortened_ip = 1;
	my @quartets = split(/:/, $ipv6_addr, -1);
	if ( scalar @quartets > 9 ) {
		_print_it('too much quartets');
		return undef;
	}

	my @full_quartets = ();
	foreach my $quartet ( @quartets ) {
		if ( $quartet eq '' && $shortened_ip ) {
			$shortened_ip = 0;
			push( @full_quartets, ('0000') x (9 - scalar @quartets) );
		} else {
			$quartet ||= 0;
			push( @full_quartets, sprintf('%04x', hex $quartet) );
		}
	}

	return lc join(':', @full_quartets);
}


# "get_min_ipv6_address" return min network address
# a:b:c:d:e:f:0:1/64 > 000a:000b:000c:000d:0000:0000:0000:0000 
# Input paramaters:
# - ipv6 address
# - network prefix
#
# Return >scalar

sub get_min_ipv6_address {
	my ($ipv6addr, $prefix) = @_;

	unless ( $ipv6addr && $prefix ) {
		_print_it('empty input params');
		return undef;
	}

	my $full_ipv6addr = convert_to_full_ipv6($ipv6addr);
	unless ( $full_ipv6addr ) {
		_print_it("cannot convert '$ipv6addr' to full view");
		return undef;
	}

	my $decimal_ipv6_addr = unpack( 'B128', pack('H4' x 8, split(/:/, $full_ipv6addr)) );
	my $decimal_ipv6_prefix = unpack( 'B128', pack('B128', '1' x $prefix . '0' x (128 - $prefix)) );

	return join(':', unpack( 'H4' x 8, pack('B128', $decimal_ipv6_addr & $decimal_ipv6_prefix) ));
}


# "get_max_ipv6_address" return max network address
# a:b:c:d:e:f:0:1/64 > 000a:000b:000c:000d:ffff:ffff:ffff:ffff
# Input paramaters:
# - ipv6 addr
# - network prefix
#
# Return >scalar

sub get_max_ipv6_address {
	my ($ipv6addr, $prefix) = @_;

	unless ($ipv6addr && $prefix) {
		_print_it('empty input params');
		return undef;
	}

	my $full_ipv6addr = convert_to_full_ipv6($ipv6addr);
	unless ( $full_ipv6addr ) {
		_print_it("cannot convert '$ipv6addr' to full view");
		return undef;
	}

	my $decimal_ipv6_addr = unpack( 'B128', pack('H4' x 8, split(/:/, $full_ipv6addr)) );
	my $decimal_ipv6_prefix = unpack( 'B128', pack('B128', '1' x $prefix . '0' x (128 - $prefix)) );

	return join(':', unpack( 'H4' x 8, pack('B128', ($decimal_ipv6_addr & $decimal_ipv6_prefix) | (~ $decimal_ipv6_prefix)) ));
}


1;
