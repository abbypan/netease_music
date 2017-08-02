#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use WWW::Mechanize::Firefox;
use File::Slurp qw/write_file slurp/;
use FindBin;
use Data::Dumper;
use JSON;
use Encode::Locale;
use Encode;
use HTML::Entities;

$| = 1;
binmode( STDIN,  ":encoding(console_in)" );
binmode( STDOUT, ":encoding(console_out)" );
binmode( STDERR, ":encoding(console_out)" );

our $MECH = WWW::Mechanize::Firefox->new();
$MECH->autodie(0);
$MECH->autoclose_tab( 1 );

my ( $album_url ) = @ARGV;

main_album( $album_url );

sub main_album {
  my ( $album_url ) = @_;

  my ( $album_id ) = $album_url =~ m#id=(\d+)$#;
  my $album_cap_file = "netease_music_$album_id.pcap";

  my $pid = fork();
  if ( $pid == 0 ) {
    system( qq[sudo tcpdump port 80 -w $album_cap_file] );
  } else {
    my $album_inf;
    for(1 .. 3){#retry 3 times
        $album_inf = view_album( $album_url, $album_cap_file );
        sleep 10;
    }
    system( qq[ps aux|grep tcpdump|grep netease_music |awk '{print \$2}'|xargs sudo kill] );
    kill 1, $pid;
    system( qq[sudo rm $album_cap_file] );
    write_file("$album_cap_file.info.json", encode_json($album_inf));
  } ## end else [ if ( $pid == 0 ) ]
} ## end sub main_album

sub view_album {
  my ( $album_url , $album_cap_file) = @_;

  my %inf;
  print "visit album url: $album_url\n";
  $MECH->get( $album_url );

  sleep 5;

  my $album_name = $MECH->xpath( '//h2', one => 1 );
  $inf{album_name} = tidy_html_string($album_name->{innerHTML});

  my $singer = $MECH->xpath( '//a[@class="s-fc7"]', one => 1 );
  $inf{singer} = tidy_html_string($singer->{innerHTML});

  mkdir(encode(locale=>"$inf{singer}-$inf{album_name}"));

  my @song = $MECH->xpath( '//div[@id="song-list-pre-cache"]//tbody//tr' );
  @song = map { $_->{outerHTML} } @song;

  my $i = 1;
  for my $c ( @song ) {
      my ( $song_id ) = $c =~ m#/song\?id=(\d+)"#;
      next unless ( $song_id );

      my ($class) = $c=~m#^.*?class="(.*?)"#;
      my $is_valid = $class=~/js-dis/ ? 0 : 1;

      my ( $u, $t ) = $c =~ m#<a href="(.+?)"><b title="(.+?)">#;
      $u = "http://music.163.com$u";
      $t = tidy_html_string($t);
      my $j = sprintf( "%02d", $i );
      my $song_file = "$inf{singer}-$inf{album_name}/$j.$t.mp3";

      print "visit song url: $j $t $u, is_valid: $is_valid\n";
      push @{ $inf{song} }, {
          index => $j, 
          song_title => $t, 
          url => $u, 
          song_id => $song_id, 
          is_valid => $is_valid, 
          song_file => $song_file,
      };

      $i++;

      next unless($is_valid);
      next if(-f encode(locale=>$song_file));

      $MECH->get( $u );
      sleep 5;
      print "click play button\n";

      my ( $play ) = $MECH->xpath( '//em[@class="ply"]', single => 1 );
      $MECH->synchronize( 'DOMFrameContentLoaded', sub {
              $MECH->click( $play ) if($play);
          }
      );

      sleep 10;

      my $song_url_inf = parse_album_cap( $album_cap_file );
      next unless(exists $song_url_inf->{ $song_id });
      $inf{song}[-1]{song_url} = $song_url_inf->{$song_id};
      $inf{song}[-1]{song_file} = $song_file;

      download_music($song_url_inf->{$song_id}, $song_file);
  } 

  for my $s (@{$inf{song}}){
      download_music($s->{song_url}, $s->{song_file}) if($s->{song_url});
  }

  return \%inf;
} ## end sub view_album

sub download_music {
    my ($song_url, $song_file) = @_;
    return if(-f encode(locale=>$song_file));
    my $cmd=qq[curl -L -C - -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:53.0) Gecko/20100101 Firefox/53.0" -H "Accept-Encoding: gzip, deflate" "$song_url" -o "$song_file"];
    print "$cmd\n";
    system(encode(locale=>$cmd));
}

sub parse_album_cap {
  my ( $cap_file ) = @_;
  my $c = `tshark -r "$cap_file" -E 'separator=;' -T fields -e http.file_data|grep "\\.mp3"`;
  my @cc = split /\n/s, $c;
  my %res;
  for my $x ( @cc ) {
    next unless($x=~/\Q{"data":/);
    my $r  = decode_json( $x );
    my $rr = $r->{data}[0];
    $res{ $rr->{id} } = $rr->{url};
  }
#print Dumper(\%res);
  return \%res;
}

sub tidy_html_string {
    my ($s) = @_;
    my $ss = decode_entities($s);
    $ss=~s/[\|\/\\:;<>\s\?\[\]\{\}\*]+/_/g;
    return $ss;
}
