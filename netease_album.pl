#!/usr/bin/perl

use WWW::Mechanize::Firefox;
use Data::Dumper;
use JSON;
use Encode::Locale;
use Encode;
use utf8;
$| = 1;
binmode( STDIN,  ":encoding(console_in)" );
binmode( STDOUT, ":encoding(console_out)" );
binmode( STDERR, ":encoding(console_out)" );

our $MECH = WWW::Mechanize::Firefox->new();
$MECH->autoclose_tab( 1 );

my ( $album_url ) = @ARGV;

main_album( $album_url );

sub main_album {
  my ( $album_url ) = @_;

  my ( $album_id ) = $album_url =~ m#id=(\d+)$#;
  my $album_cap_file = "netease_album_$album_id.pcap";

  my $pid = fork();
  if ( $pid == 0 ) {
    system( qq[sudo tcpdump port 80 -w $album_cap_file] );
  } else {
    my $album_inf = view_album( $album_url );
    sleep 3;
    system( qq[ps aux|grep tcpdump|grep $album_cap_file |awk '{print \$2}'|xargs sudo kill] );

    my $song_url_inf = parse_album_cap( $album_cap_file );

    my $dir = encode( locale => "$album_inf->{singer}-$album_inf->{album_name}" );
    mkdir $dir;
    for my $s ( @{ $album_inf->{song} } ) {
      next unless ( exists $song_url_inf->{ $s->{song_id} } );
      my $song_url = $song_url_inf->{ $s->{song_id} };

      my $j = sprintf( "%02d", $s->{index} );
      my ( $suffix ) = $song_url =~ m#\.([^\.\?]+?)$#s;
      my $song_file = "$album_inf->{singer}-$album_inf->{album_name}/$j.$s->{song_title}.$suffix";
      print "download song: $song_file\n";
      my $cmd = qq[curl -L -C - "$song_url" -o "$song_file"];
      print "$cmd\n";
      system( $cmd);
      $i++;
    }

    kill 1, $pid;
    system( qq[sudo rm $album_cap_file] );
  } ## end else [ if ( $pid == 0 ) ]
} ## end sub main_album

sub parse_album_cap {
  my ( $cap_file ) = @_;
  my $c = `tshark -r "$cap_file" -E 'separator=;' -T fields -e http.file_data|grep "\\.mp3"`;
  my @cc = split /\n/s, $c;
  my %res;
  for my $x ( @cc ) {
    my $r  = decode_json( $x );
    my $rr = $r->{data}[0];
    $res{ $rr->{id} } = $rr->{url};
  }

  return \%res;
}

sub view_album {
  my ( $album_url ) = @_;

  my %inf;
  print "visit album url: $album_url\n";
  $MECH->get( $album_url );

  my $album_name = $MECH->xpath( '//h2', one => 1 );
  $inf{album_name} = $album_name->{innerHTML};

  my $singer = $MECH->xpath( '//p[@class="intr"]//a', one => 1 );
  $inf{singer} = $singer->{innerHTML};

  my @song = $MECH->xpath( '//div[@id="song-list-pre-cache"]//a' );
  @song = map { $_->{outerHTML} } @song;

  my $i = 1;
  for my $c ( @song ) {
    my ( $song_id ) = $c =~ m#/song\?id=(\d+)"#;
    next unless ( $song_id );
    my ( $u, $t ) = $c =~ m#<a href="(.+?)"><b title="(.+?)">#;
    $u = "http://music.163.com$u";
    push @{ $inf{song} }, { index => $i, song_title => $t, url => $u, song_id => $song_id };
    print "visit song url: $i $t $u\n";
    $MECH->get( $u );
    sleep 2;
    print "click play button: $i $t $u\n";
    my ( $play ) = $MECH->xpath( '//em[@class="ply"]', single => 1 );
    $MECH->click( $play );
    $i++;
    sleep 3;
  }
  return \%inf;
} ## end sub view_album

