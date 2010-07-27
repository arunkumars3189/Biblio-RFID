#!/usr/bin/perl

=head1 RFID-JSONP-server

This is simpliest possible JSONP server which provides local web interface to RFID readers

Usage:

  ./scripts/RFID-JSONP-server.pl

=cut

use strict;
use warnings;

use Data::Dump qw/dump/;

use JSON;
use IO::Socket::INET;

my $debug = 1;

my $listen_port = 9000;                  # pick something not in use
my $server_url  = "http://localhost:$listen_port";


use lib 'lib';
use RFID::Serial::3M810;
my $rfid = RFID::Serial::3M810->new;

my $index_html;
{
	local $/ = undef;
	$index_html = <DATA>;
}

sub http_server {

	my $server = IO::Socket::INET->new(
		Proto     => 'tcp',
		LocalPort => $listen_port,
		Listen    => SOMAXCONN,
		Reuse     => 1
	);
								  
	die "can't setup server: $!" unless $server;

	print "Server $0 ready at $server_url\n";

	while (my $client = $server->accept()) {
		$client->autoflush(1);
		my $request = <$client>;

		warn "WEB << $request\n" if $debug;
		my $path;

		if ($request =~ m{^GET (/.*) HTTP/1.[01]}) {
			my $method = $1;
			my $param;
			if ( $method =~ s{\?(.+)}{} ) {
				foreach my $p ( split(/[&;]/, $1) ) {
					my ($n,$v) = split(/=/, $p, 2);
					$param->{$n} = $v;
				}
				warn "WEB << param: ",dump( $param ) if $debug;
			}
			$path = $method;

			if ( $path eq '/' ) {
				print $client "HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\n$index_html";
			} elsif ( $method =~ m{/scan} ) {
				my $tags = $rfid->scan;
				my $json = {
					time => time(),
					tags => $tags,
				};
				print $client "HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n",
					$param->{callback}, "(", to_json($json), ")\r\n";
			} elsif ( $method =~ m{/program} ) {

				my $status = 501; # Not implementd

				foreach my $p ( keys %$param ) {
					next unless $p =~ m/^(E[0-9A-F]{15})$/;
					my $tag = $1;
					my $content = "\x04\x11\x00\x01" . $param->{$p};
					$content = "\x00" if $param->{$p} eq 'blank';
					$status = 302;

					warn "PROGRAM $tag $content\n";
					write_tag( $tag, $content );
					secure_tag_with( $tag, $param->{$p} =~ /^130/ ? 'DA' : 'D7' );
				}

				print $client "HTTP/1.0 $status $method\r\nLocation: $server_url\r\n\r\n";

			} elsif ( $method =~ m{/secure(.js)} ) {

				my $json = $1;

				my $status = 501; # Not implementd

				foreach my $p ( keys %$param ) {
					next unless $p =~ m/^(E[0-9A-F]{15})$/;
					my $tag = $1;
					my $data = $param->{$p};
					$status = 302;

					warn "SECURE $tag $data\n";
					secure_tag_with( $tag, $data );
				}

				if ( $json ) {
					print $client "HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n",
						$param->{callback}, "({ ok: 1 })\r\n";
				} else {
					print $client "HTTP/1.0 $status $method\r\nLocation: $server_url\r\n\r\n";
				}

			} else {
				print $client "HTTP/1.0 404 Unkown method\r\n\r\n";
			}
		} else {
			print $client "HTTP/1.0 500 No method\r\n\r\n";
		}
		close $client;
	}

	die "server died";
}

http_server;

__DATA__
<html>
<head>
<title>RFID JSONP</title>
<script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js"></script>
<style type="text/css">
.status {
	background: #ff8;
}

.da {
	background: #fcc;
}

.d7 {
	background: #cfc;
}

label[for=pull-reader] {
	position: absolute;
	top: 1em;
	right: 1em;
	background: #eee;
}

</style>
<script type="text/javascript">

function got_visible_tags(data,textStatus) {
	var html = 'No tags in range';
	if ( data.tags ) {
		html = '<ul class="tags">';
		$.each(data.tags, function(i,tag) {
			console.debug( i, tag );
			html += '<li><tt class=' + tag.security + '>' + tag.sid;
			if ( tag.content ) {
				html += ' <a href="https://koha-dev.rot13.org:8443/cgi-bin/koha/members/member.pl?member=' + tag.content + '" title="lookup in Koha" target="koha-lookup">' + tag.content + '</a>';
				html += '</tt>';
				html += '<form method=get action=program style="display:inline">'
					+ '<input type=hidden name='+tag.sid+' value="blank">'
					+ '<input type=submit value="Blank" onclick="return confirm(\'Blank tag '+tag.sid+'\')">'
					+ '</form>'
				;
			} else {
				html += '</tt>';
				html += ' <form method=get action=program style="display:inline">'
					+ '<!-- <input type=checkbox name=secure value='+tag.sid+' title="secure tag"> -->'
					+ '<input type=text name='+tag.sid+' size=12>'
					+ '<input type=submit value="Program">'
					+ '</form>'
				;
			}
		});
		html += '</ul>';
	}

	var arrows = Array( 8592, 8598, 8593, 8599, 8594, 8600, 8595, 8601 );

	html = '<div class=status>'
		+ textStatus
		+ ' &#' + arrows[ data.time % arrows.length ] + ';'
		+ '</div>'
		+ html
		;
	$('#tags').html( html );
	window.setTimeout(function(){
		scan_tags();
	},200);	// re-scan every 200ms
};

function scan_tags() {
	console.info('scan_tags');
	if ( $('input#pull-reader').attr('checked') )
		$.getJSON("http://localhost:9000/scan?callback=?", got_visible_tags);
}

$(document).ready(function() {
		$('input#pull-reader').click( function() {
			scan_tags();
		});
		$('input#pull-reader').attr('checked', true); // force check on load

		$('div#tags').click( function() {
			$('input#pull-reader').attr('checked', false);
		} );

		scan_tags();
});
</script>
</head>
<body>

<h1>RFID tags in range</h1>

<label for=pull-reader>
<input id=pull-reader type=checkbox checked=1>
active
</label>

<div id="tags">
RFID reader not found or driver program not started.
</div>

</body>
</html>