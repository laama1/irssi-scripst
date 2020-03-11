use warnings;
use strict;
use Irssi;
use utf8;		# allow utf8 in regex
use Encode;
use JSON;
use DateTime;
use POSIX;
use Time::Piece;
use feature 'unicode_strings';

#use Number::Format qw('format_number' :vars);
use Number::Format qw(:subs :vars);
# didnt find --laama use CLDR::Number;
# $DECIMAL_POINT = ',';
my $fi = new Number::Format(-decimal_point => ',');

use Math::Trig; # for apparent temp
#use URI::Escape;
use Data::Dumper;

binmode STDIN, ':utf8';
binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';
#binmode STDOUT, ":encoding(utf8)";
#binmode STDIN, ":encoding(utf8)";
#binmode STDERR, ":encoding(utf8)";
#binmode FILE, ':utf8';
#use open ':std', ':encoding(utf8)';

use Data::Dumper;

use KaaosRadioClass;				# LAama1 13.11.2016

use vars qw($VERSION %IRSSI);
$VERSION = '20200311';
%IRSSI = (
	authors     => 'LAama1',
	contact     => 'LAama1@ircnet',
	name        => 'openweathermap',
	description => 'Fetches weather data from openweathermap.org',
	license     => 'Fublic Domain',
	url         => 'http://kaaosradio.fi',
	changed     => $VERSION,
);

my $apikeyfile = Irssi::get_irssi_dir(). '/scripts/openweathermap_apikey';
my $apikey;
#my $url = 'https://api.openweathermap.org/data/2.5/weather?q=';
my $url = 'https://api.openweathermap.org/data/2.5/weather?';
my $forecastUrl = 'https://api.openweathermap.org/data/2.5/forecast?q=';
my $areaUrl = 'https://api.openweathermap.org/data/2.5/find?cnt=5&lat=';
my $DEBUG = 1;
my $DEBUG1 = 1;
my $myname = 'openweathermap.pl';
my $db = Irssi::get_irssi_dir(). '/scripts/openweathermap.db';
my $dbh;	# database handle

=pod
UTF8 emojis:
⛈️ Cloud With Lightning and Rain
☁️ Cloud
🌩️ Cloud With Lightning
🌧️ Cloud With Rain
🌨️ Cloud With Snow
❄️ Snow flake
🌪️ Tornado

🌫️ Fog
🌁 Foggy (city)
⚡ High Voltage

☔ Umbrella With Rain Drops
🌂 closed umbrella
🌈 rainbow
🌥️ Sun Behind Large Cloud
⛅ Sun Behind Cloud
🌦️ Sun Behind Rain Cloud
🌤️ Sun Behind Small Cloud

🌄 sunrise over mountains
🌅 sunrise
🌇 sunset over buildings
🌞 Sun With Face
☀️ Sun
🌆 cityscape at dusk
🌉 bridge at night
🌃 night with stars

🌊 water wave
🌀 cyclone
🌬️ Wind Face
💨 dashing away
🍂 fallen leaf
🌋 volcano
🌏 earth globe asia australia
🌟 glowing star
🌠 shooting star
🎆 fireworks

🌌 milky way
🌛 first quarter moon face
🌝 full moon face
🌜 last quarter moon face
🌚 new moon face
🌙 crescent moon
🌑 new moon
🌓 first quarter moon
🌖 Waning gibbous moon
🌒 waxing crescent moon
🌔 waxing gibbous moon

🦄 Unicorn Face
🎠 carousel horse
https://emojipedia.org/moon-viewing-ceremony/

=cut


open APIKEY_fh, '<:encoding(UTF-8)', $apikeyfile or die $myname.': Unable to open APIKEY file. '. $!;
$apikey = <APIKEY_fh>;
chomp $apikey;
close APIKEY_fh or die $myname.': Unable to close APIKEY file. '. $!;


unless (-e $db) {
	unless(open FILE, '>:utf8',$db) {
		Irssi::print("$myname: Unable to create or write DB file: $db");
		die;
	}
	close FILE;
	if (CREATEDB() == 0) {
		Irssi::print("$myname: Database file created.");
	}
}

sub replace_with_emoji {
	my ($string, $sunrise, $sunset, $comparetime, @rest) = @_;
	# TODO: scattered clouds, light intensity rain
	#dp(__LINE__.": string: $string, sunrise: $sunrise, sunset: $sunset, comparetime: $comparetime");
	my $sunmoon = get_sun_moon($sunrise, $sunset, $comparetime);
	$string =~ s/fog|mist/🌫️ /ui;
	$string =~ s/wind/💨 /ui;
	$string =~ s/snow/❄️ /ui;
	$string =~ s/clear sky/$sunmoon /u;
	$string =~ s/Sky is Clear/$sunmoon /u;
	$string =~ s/Clear/$sunmoon /u;			# short desc
	$string =~ s/Clouds/☁️ /u;				# short desc
	$string =~ s/Rain/🌧️ /u;				# short desc
	$string =~ s/light rain/☔ /u;
	$string =~ s/thunderstorm/⚡ /u;
	$string =~ s/scattered clouds/☁ /u;
	my $sunup = is_sun_up($sunrise, $sunset, $comparetime);
	if ($sunup == 1) {
		$string =~ s/overcast clouds/🌥️ /sui;
		$string =~ s/broken clouds/⛅ /sui;
		$string =~ s/few clouds/🌤️ /sui;
		$string =~ s/light intensity shower rain/🌦️ /su;
		$string =~ s/shower rain/🌧️ /su;
	} elsif ($sunup == 0) {
		$string =~ s/shower rain/🌧️ /su;
		$string =~ s/broken clouds/☁ /su;
	}
	return $string;
}

# TODO: timezone
# params: sunrise, sunset, time to compare: unixtime
sub is_sun_up {
	my ($sunrise, $sunset, $comparetime, $tz, @rest) = @_;
	#dp(__LINE__." sunrise: $sunrise, sunset: $sunset, comaparetime: $comparetime");
	$sunrise =~ s/(.*?)T(.*)/$2/;
	$sunset =~ s/(.*?)T(.*)/$2/;
	$comparetime =~ s/(.*?) (.*)/$2/;
	#dp(__LINE__." sunrise: $sunrise, sunset: $sunset, comaparetime: $comparetime");
	if ($comparetime > $sunset || $comparetime < $sunrise) {
		#dp(__LINE__.': sun is down');
		return 0;
	}
	#dp(__LINE__.': sun is up');
	return 1;
}

sub get_sun_moon {
	my ($sunrise, $sunset, $comparetime, $tz, @rest) = @_;
	#dp(__LINE__.": sunrise: $sunrise, sunset: $sunset, comparetime: $comparetime");
	if (is_sun_up($sunrise, $sunset, $comparetime) == 1) {
		return '🌞';
	}
	return omaconway();
}

sub omaconway {
	# John Conway method
	#my ($y,$m,$d);
	chomp(my $y = `date +%Y`);
	chomp(my $m = `date +%m`);
	chomp(my $d = `date +%d`);

	my $r = $y % 100;
	$r %= 19;
	if ($r > 9) { $r-= 19; }
	$r = (($r * 11) % 30) + $m + $d;
	if ($m < 3) { $r += 2; }
	$r -= 8.3;              # year > 2000

	$r = ($r + 0.5) % 30;	#test321
	my $age = $r;
	$r = 7/30 * $r + 1;

=pod
      0: 'New Moon'        🌑
      1: 'Waxing Crescent' 🌒
      2: 'First Quarter',  🌓
      3: 'Waxing Gibbous', 🌔
      4: 'Full Moon',      🌕
      5: 'Waning Gibbous', 🌖
      6: 'Last Quarter',   🌗
      7: 'Waning Crescent' 🌘
=cut

	my @moonarray = ('🌑', '🌒', '🌓', '🌔', '🌕', '🌖', '🌗', '🌘');
	return $moonarray[$r];
}

# param: searchword, returns json answer or 0
sub FINDWEATHER {
	my ($searchword, @rest) = @_;
	$searchword = stripc($searchword);
	Irssi::print("Searchword: $searchword");
	my $newurl;
	my $urltail = $searchword.'&units=metric&appid='.$apikey;
	if ($searchword =~ /\d{5,}/) {
		$newurl = $url.'zip=';
		$urltail = $searchword.',fi&units=metric&appid='.$apikey;;		# Search post numbers only from finland
	} else {
		$newurl = $url.'q=';
	}
	Irssi::print("url: $newurl".$urltail);
	my $data = KaaosRadioClass::fetchUrl($newurl.$urltail, 0);
	if ($data eq '-1') {
		# city not found
		my ($lat, $lon, $name) = GETCITYCOORDS($searchword);
		return 0 unless defined $name;
		$data = KaaosRadioClass::fetchUrl($newurl.$urltail, 0);
		return 0 if ($data eq '-1');
	}

	my $json = decode_json($data);
	$dbh = KaaosRadioClass::connectSqlite($db);
	SAVECITY($json);
	SAVEDATA($json);
	return $json;
}

sub FINDFORECAST {
	my ($searchword, @rest) = @_;
	my $returnstring = "\002klo\002 ";	# bold

	$searchword = stripc($searchword);
	my $data = KaaosRadioClass::fetchUrl($forecastUrl.$searchword.'&units=metric&appid='.$apikey, 0);

	if ($data eq '-1') {
		my ($lat, $lon, $name) = GETCITYCOORDS($searchword);
		$data = KaaosRadioClass::fetchUrl($forecastUrl.$name.'&units=metric&appid='.$apikey, 0) if defined $name;
		return 0 if ($data eq '-1');
	}

	my $json = decode_json($data);
	#da($json,__LINE__.': json:');
	my $index = 0;
	foreach my $item (@{$json->{list}}) {
		if ($index >= 7) {
			# max 8 items: 8x 3h = 24h
			last;
		}
		if ($index == 0) {
			$returnstring = $json->{city}->{name} . ', '.$json->{city}->{country}.': '.$returnstring;
		}
		
		#my $weathericon = replace_with_emoji($item->{weather}[0]->{main}, localtime($json->{city}->{sunrise})->datetime,
		#									localtime($json->{city}->{sunset})->datetime, $item->{dt_txt});
		my $weathericon = replace_with_emoji($item->{weather}[0]->{main}, $json->{city}->{sunrise},
											$json->{city}->{sunset}, $item->{dt});


		my ($sec, $min, $hour, $mday) = localtime($item->{dt});
		$returnstring .= "\002".sprintf('%.2d', $hour) .":\002 $weathericon ".$fi->format_number($item->{main}->{temp}, 1) .'°C, ';
		$index++;
	}
	return $returnstring;
}

sub FINDAREAWEATHER {
	my ($city, @rest) = @_;
	my ($lat, $lon, $name) = GETCITYCOORDS($city);                                  # find existing city from DB by search word
	FINDWEATHER($city) unless ($lat && $lon && $name);                              # find city from API if not found from DB
	($lat, $lon, $name) = GETCITYCOORDS($city) unless ($lat && $lon && $name);      # find existing city again from DB
	return 'City not found from DB or API.' unless ($lat && $lon && $name);

	my $searchurl = $areaUrl.$lat."&lon=$lon&units=metric&appid=".$apikey;
	my $data = KaaosRadioClass::fetchUrl($searchurl, 0);

	if ($data eq '-1') {
		return 0;
	}

	my $json = decode_json($data);
	my $sayline;
	foreach my $city (@{$json->{list}}) {
		# TODO: get city coords from API and save to DB
		$sayline .= getSayLine2($city) . '. ';
	}
	return $sayline;
}

# format the message in another way
sub getSayLine2 {
	my ($json, @rest) = @_;
	if ($json == 0) {
		return;
	}

	my $weatherdesc;
	my $index = 1;
	foreach my $item (@{$json->{weather}}) {
		if ($index > 1) {
			$weatherdesc .= ', ';
		}
		$weatherdesc .= $item->{description};
		$index++;
	}
	# FIXME: fix time
	my $returnvalue = $json->{name}.': '.$fi->format_number($json->{main}->{temp}, 1).'°C, '.replace_with_emoji($weatherdesc, $json->{sys}->{sunrise}, $json->{sys}->{sunset}, time);
	return $returnvalue;
}

# format the message
sub getSayLine {
	my ($json, @rest) = @_;
	if ($json eq '0') {
		dp('getSayLine json = 0');
		return 0;
	}
	da($json);
	my $tempmin = $fi->format_number($json->{main}->{temp_min}, 1);
	my $tempmax = $fi->format_number($json->{main}->{temp_max}, 1);
	my $temp;
	if ($tempmin ne $tempmax) {
		$temp = "($tempmin…$tempmax)°C"
	} else {
		$temp = $fi->format_number($json->{main}->{temp}, 1).'°C';
	}
	my $apptemp = get_apperent_temp($json->{main}->{temp}, $json->{main}->{humidity}, $json->{wind}->{speed}, $json->{clouds}->{all}, $json->{coord}->{lat}, $json->{dt});
	dp(__LINE__.': apparent temp: '.$apptemp);
	dp(__LINE__.': feels like: '.$json->{main}->{feels_like});
	my $sky = '';
	#if (is_sun_up(localtime($json->{sys}->{sunrise})->datetime,
	#				localtime $json->{sys}->{sunset},
	#				localtime->datetime) == 0) {
	#	$sky = ' --> '. omaconway();
	#}
	if ($apptemp) {
		$apptemp = ', (~ '.$fi->format_number($apptemp, 1).'°C)';
	} else {
		$apptemp = '';
	}

	my $sunrise = '🌄 '.localtime($json->{sys}->{sunrise})->strftime('%H:%M');
	my $sunset = '🌆 ' .localtime($json->{sys}->{sunset})->strftime('%H:%M');
	my $wind = '💨 '. $fi->format_number($json->{wind}->{speed}, 1). ' m/s';
	my $city = $json->{name};
	if ($city eq 'Kokkola') {
		$city = '🦄 Kokkola';
	}
	my $weatherdesc = '';
	my $index = 1;
	foreach my $item (@{$json->{weather}}) {
		da(__LINE__.': weather:', $item) if $DEBUG1;
		if ($index > 1) {
			$weatherdesc .= ', ';
		}
		$weatherdesc .= $item->{description};
		$index++;
	}
	da(__LINE__.': weatherdesc:',$weatherdesc, 'weather descriptions:',$json->{weather}) if $DEBUG1;
	my $newdesc = replace_with_emoji($weatherdesc, $json->{sys}->{sunrise}, $json->{sys}->{sunset}, $json->{dt});
	my $returnvalue = $city.', '.$json->{sys}->{country}.': '.$temp.', '.$newdesc.'. '.$sunrise.', '.$sunset.', '.$wind.$sky.$apptemp;
	return $returnvalue;
}

use constant SOLAR_CONSTANT => 1395; # solar constant (w/m2)
use constant TRANSMISSIONCOEFFICIENTCLEARDAY => 0.81;
use constant TRANSMISSIONCOEFFICIENTCLOUDY => 0.62;
# copied from android app: your local weather
# TODO: mention license GPL?
# params:
# $dryBulbTemperature = degrees in celsius ?
# $humidity = percent
# $windSpeed = m/s
# $cloudiness = percent
# $latitude = degrees?
# $timestamp = unixtime
sub get_apperent_temp {
	my ($dryBulbTemperature, $humidity, $windSpeed, $cloudiness, $latitude, $timestamp, @rest) = @_;

	my $e = ($humidity / 100.0) * 6.105 * exp (17.27*$dryBulbTemperature / (237.7 + $dryBulbTemperature));
	my $cosOfZenithAngle = get_cos_of_zenith_angle(deg2rad($latitude), $timestamp);

	my $secOfZenithAngle = 1/ $cosOfZenithAngle;
	my $transmissionCoefficient = TRANSMISSIONCOEFFICIENTCLEARDAY - (TRANSMISSIONCOEFFICIENTCLEARDAY - TRANSMISSIONCOEFFICIENTCLOUDY) * ($cloudiness/100.0);
	my $calculatedIrradiation = 0;
	if ($cosOfZenithAngle > 0) {
            $calculatedIrradiation = (SOLAR_CONSTANT * $cosOfZenithAngle * $transmissionCoefficient ** $secOfZenithAngle)/10;
    }
	my $apparentTemperature = $dryBulbTemperature + (0.348 * $e) - (0.70 * $windSpeed) + ((0.70 * $calculatedIrradiation)/($windSpeed + 10)) - 4.25;
	dp(__LINE__.': apparent temp: '.$apparentTemperature);
	return sprintf "%.1f", $apparentTemperature;
}
sub get_cos_of_zenith_angle {
	my ($latitude, $timestamp, @rest) = @_;
	my $declination = deg2rad(-23.44 * cos(deg2rad((360.0/365.0) * (9 + get_day_of_year($timestamp)))));
	my $hour_angle = ((12 * 60) - get_minute_of_day($timestamp)) * 0.25;
	return sin $latitude * sin $declination + (cos $latitude * cos $declination * cos deg2rad($hour_angle));
}
sub get_day_of_year {
	my ($timestamp, $tz, @rest) = @_;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime $timestamp;
	return $yday +1;
}
sub get_minute_of_day {
	my ($timestamp, $tz, @rest) = @_;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime $timestamp;
	return $hour*60 + $min;
}

sub GETCITYCOORDS {
	my ($city, @rest) = @_;
	$city = "%${city}%";
	my $sql = 'SELECT DISTINCT LAT,LON,NAME from CITIES where NAME Like ?;';
	my @results = bind_sql($sql, $city);
	return $results[0], $results[1], decode('UTF-8', $results[2]);
}

# save new city to database if it does not exist
sub SAVECITY {
	my ($json, @rest) = @_;
	#dp(__LINE__.':SAVECITY city: '.$city);
	my $now = time;
	# TODO: bind params
	my $sql = "INSERT OR IGNORE INTO CITIES (ID, NAME, COUNTRY, PVM, LAT, LON) VALUES ($json->{id}, '$json->{name}', '$json->{sys}->{country}', $now, '$json->{coord}->{lat}', '$json->{coord}->{lon}')";
	#my $sql = "INSERT OR IGNORE INTO CITIES (ID, NAME, COUNTRY, PVM, LAT, LON) VALUES (?, ?, ?, ?, ?, ?)";
	#my @array = ($json->{id}, $json->{name}, $json->{sys}->{country}, $now, $json->{coord}->{lat}, $json->{coord}->{lon});
	#return KaaosRadioClass::bindSQL($db, $sql, @array);
	return KaaosRadioClass::writeToOpenDB($dbh, $sql);
}

sub SAVEDATA {
	my ($json, @rest) = @_;
	my $now = time;
	my $name = $json->{name};
	my $country = $json->{sys}->{country} || '';
	my $id = $json->{id} || -1;
	my $sunrise = $json->{sys}->{sunrise} || 0;
	my $sunset = $json->{sys}->{sunset} || 0;
	my $weatherdesc = $json->{weather}[0]->{description} || '';
	my $windspeed = $json->{wind}->{speed} || 0;
	my $winddir = $json->{wind}->{deg} || 0;
	my $tempmax = $json->{main}->{temp_max} || 0;
	my $humidity = $json->{main}->{humidity} || 0;
	my $pressure = $json->{main}->{pressure} || 0;
	my $tempmin = $json->{main}->{temp_min} || 0;
	my $temp = $json->{main}->{temp} || 0;
	my $lat = $json->{coord}->{lat} || 0;
	my $long = $json->{coord}->{lon} || 0;
									#1	#2	 #2			#4		#5		#6		#7			#8			#9		#10		#11		#12		#13			#14		#15	#16	
	my $stmt = "INSERT INTO DATA (CITY, PVM, COUNTRY, CITYID, SUNRISE, SUNSET, DESCRIPTION, WINDSPEED, WINDDIR, TEMPMAX, TEMP, HUMIDITY, PRESSURE, TEMPMIN, LAT, LON)
	 VALUES ('$name', $now, '$country', $id, $sunrise, $sunset, '$weatherdesc', '$windspeed', '$winddir', '$tempmax', '$temp', '$humidity', '$pressure', '$tempmin', '$lat', '$long')";
	#my $stmt = "INSERT INTO DATA (CITY, PVM, COUNTRY, CITYID, SUNRISE, SUNSET, DESCRIPTION, WINDSPEED, WINDDIR, TEMPMAX, TEMP, HUMIDITY, PRESSURE, TEMPMIN, LAT, LON)
	# VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
	#my @params = ($name, $now, $country, $id, $sunrise, $sunset, $weatherdesc, $windspeed, $winddir, $tempmax, $temp, $humidity, $pressure, $tempmin, $lat, $long);
	#dp(__LINE__.':SAVEDATA name: '.$name);
	return KaaosRadioClass::writeToOpenDB($dbh, $stmt);
}

sub CREATEDB {
	$dbh = KaaosRadioClass::connectSqlite($db);
	my $stmt = 'CREATE TABLE IF NOT EXISTS CITIES (ID int, NAME TEXT, COUNTRY text, PVM INT, LAT TEXT, LON TEXT, PRIMARY KEY(ID, NAME))';

	my $rv = KaaosRadioClass::writeToOpenDB($dbh, $stmt);
	if($rv != 0) {
   		Irssi::print ("$myname: DBI Error $rv");
		return -1;
	} else {
   		Irssi::print("$myname: Table CITIES created successfully");
	}

	my $stmt2 = 'CREATE TABLE IF NOT EXISTS DATA (CITY TEXT primary key, PVM INT, COUNTRY TEXT, CITYID int, SUNRISE int, SUNSET int, DESCRIPTION text, WINDSPEED text, WINDDIR text,
	TEMPMAX text, TEMP text, HUMIDITY text, PRESSURE text, TEMPMIN text, LAT text, LON text)';
	my $rv2 = KaaosRadioClass::writeToOpenDB($dbh, $stmt2);
	if($rv2 < 0) {
   		Irssi::print ("$myname: DBI Error: $rv2");
		return -2;
	} else {
   		Irssi::print("$myname: Table DATA created successfully");
	}

	$dbh = KaaosRadioClass::closeDB($dbh);
	return 0;
}

sub bind_sql {
	my ($sql, @params, @rest) = @_;
	my $dbh = KaaosRadioClass::connectSqlite($db);							# DB handle
	my $sth = $dbh->prepare($sql) or return $dbh->errstr;	# Statement handle
	$sth->execute(@params) or return ($dbh->errstr);
	my @results;
	my $idx = 0;
	while(my @row = $sth->fetchrow_array) {
		push @results, @row;
		$idx++;
	}
	$sth->finish();
	$dbh->disconnect();
	#dp(__LINE__.': -- How many results: '. $idx);
	#da(@results);
	#print Dumper(@results);
	return @results;
}

sub filter_keyword {
	my ($msg, @rest) = @_;
	$msg = decode('UTF-8', $msg);

	my $returnstring;
	if ($msg =~ /\!(sää |saa |s )(.*)$/ui) {
		return if KaaosRadioClass::floodCheck() > 0;
		my $city = $2;
		$dbh = KaaosRadioClass::connectSqlite($db);
		$returnstring = getSayLine(FINDWEATHER($city));
		$dbh = KaaosRadioClass::closeDB($dbh);
	} elsif ($msg =~ /\!(se )(.*)$/i) {
		return if KaaosRadioClass::floodCheck() > 0;
		my $city = $2;
		$dbh = KaaosRadioClass::connectSqlite($db);
		$returnstring = FINDFORECAST($city);
		$dbh = KaaosRadioClass::closeDB($dbh);
	} elsif ($msg =~ /\!(sa )(.*)$/i) {
		return if KaaosRadioClass::floodCheck() > 0;
		my $city = $2;
		$dbh = KaaosRadioClass::connectSqlite($db);
		$returnstring = FINDAREAWEATHER($city);
		$dbh = KaaosRadioClass::closeDB($dbh);
	}
	return $returnstring;
}

sub stripc {
	my ($word, @rest) = @_;
	$word =~ s/['~"`;]//g;
	return $word;
}

# debug print
sub dp {
	my ($string, @rest) = @_;
	if ($DEBUG == 1) {
		print "\n$myname debug: ".$string;
	}
	return;
}

# debug print array
sub da {
	my (@array, @rest) = @_;
	print "\n$myname debugarray:";
	print Dumper(@array) if $DEBUG == 1;
	return;
}

sub sig_msg_pub {
	my ($server, $msg, $nick, $address, $target) = @_;
	return if ($nick eq $server->{nick});   # self-test

	# Check we have an enabled channel
	my $enabled_raw = Irssi::settings_get_str('openweathermap_enabled_channels');
	my @enabled = split / /, $enabled_raw;
	return unless grep /$target/, @enabled;
	my $sayline = filter_keyword($msg);
	$server->command("msg -channel $target $sayline") if $sayline;
	return;
}

sub sig_msg_priv {
	my ($server, $msg, $nick, $address) = @_;
	return if ($nick eq $server->{nick});		# self-test
	my $sayline = filter_keyword($msg);
	$server->command("msg $nick $sayline") if $sayline;
	return;
}

sub sig_msg_pub_own {
	my ($server, $msg, $target) = @_;
	dp(__LINE__.': own public');
	sig_msg_pub($server, $msg, $server->{nick}, 'none', $target);
	return;
}

Irssi::settings_add_str('openweathermap', 'openweathermap_enabled_channels', '');

Irssi::signal_add('message public', 'sig_msg_pub');
Irssi::signal_add('message private', 'sig_msg_priv');
#Irssi::signal_add('message own_public', 'sig_msg_pub_own');
Irssi::print("$myname v. $VERSION loaded.");
Irssi::print('New commands:');
Irssi::print('/set openweathermap_enabled_channels #channel1 #channel2');
Irssi::print("Enabled on:\n". Irssi::settings_get_str('openweathermap_enabled_channels'));
