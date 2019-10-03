use strict;
use warnings;

use Irssi;
use vars qw($VERSION %IRSSI);
#use Irssi::Irc;
use Data::Dumper;
use XML::LibXML;

#require "$ENV{HOME}/.irssi/scripts/irssi-scripts/KaaosRadioClass.pm";
use KaaosRadioClass;

$VERSION = '0.1';
%IRSSI = (
	authors => 'LAama1',
	contact => 'LAama1@ircnet',
	name => 'hamqsl',
	description => 'Radiokeli -skripti.',
	license => 'BSD',
	url => 'http://www.kaaosradio.fi',
	changed => '2019-05-23',
);

my $DEBUG = 1;

my $parser = XML::LibXML->new();

sub get_help {
	return '!hams tulostaa kanavalle Radiosäästä kertovia tietoja osoitteesta http://hamqsl.com"';
}

sub pub_msg {
	my ($serverrec, $msg, $nick, $address, $target) = @_;
	#return unless ($msg =~ /$serverrec->{nick}/i);
	#return unless ($target ~~ @channels);
	return if ($nick eq $serverrec->{nick});   #self-test
	if ($msg =~ /(!help ham)/sgi) {
		return if KaaosRadioClass::floodCheck() == 1;
		my $help = getHelp();
		$serverrec->command("MSG $target $help");
	} elsif ($msg =~ /(!hams)/sgi) {
		return if KaaosRadioClass::floodCheck() == 1;
		my $xml = fetch_hams_data();
        my $newdata = parse_hams_data($xml);

		$serverrec->command("MSG $target $newdata");
		Irssi::print("hamqsl.pl: request from $nick on channel $target");
	}
}

sub parse_hams_data {
    my ($xmlobj, @rest) = @_;
    my $solarflux = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/solarflux'));
    my $aindex = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/aindex'));
    my $kindex = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/kindex'));
    my $xray = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/xray'));
    my $sunspots = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/sunspots'));
    my $protonflux = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/protonflux'));
    my $electronflux = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/electonflux'));
    my $solarwind = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/solarwind'));
    my $magfield = KaaosRadioClass::ktrim($xmlobj->findvalue('/solar/solardata/magneticfield'));
    return "Solar Flux: $solarflux, Aind: $aindex, Kind (kp): $kindex, Xray: $xray, Sun sp: $sunspots, Proton Flux: $protonflux, Elec Flux: $electronflux, Sol Wind: $solarwind km/s";
    Irssi::print(Dumper($solarflux));
}

sub fetch_hams_data {
    my $url = 'http://www.hamqsl.com/solarxml.php';
    my $textdata = KaaosRadioClass::fetchUrl($url, 0);
    my $dom = $parser->load_xml(location => $url);
    #Irssi::print(Dumper($dom));
    return $dom;
    #return KaaosRadioClass::getXML($url);
}


Irssi::signal_add_last('message public', 'pub_msg');

