#!/usr/bin/perl

package Robotics::Spykee;

=head1 NAME

Robotics::Spykee - Control interface for the Spykee robot

=head1 VERSION

Version 0.0.20100905

=cut

our $VERSION = '0.0.20100905';

=head1 SYNOPSIS

Perl module to locate and communicate with a Spykee robot.

Information about the robot is available from
http://www.spykeeworld.com/

=cut

use strict;
use warnings;
use diagnostics;
use Socket;
use IO::Select;
use IO::Socket;

my $PACKET_HEADER_SIZE            = 5;
my $PACKET_DATA_SIZE_MAX          = (32*1024);

my $PACKET_TYPE_AUDIO             =  1;
my $PACKET_TYPE_VIDEO             =  2;
my $PACKET_TYPE_POWER        =  3;
my $PACKET_TYPE_MOVE         =  5;
my $PACKET_TYPE_FILE         =  6;
my $PACKET_TYPE_PLAY         =  7;
my $PACKET_TYPE_STOP         =  8;
my $PACKET_TYPE_AUTH_REQUEST = 10;
my $PACKET_TYPE_AUTH_REPLY   = 11;
my $PACKET_TYPE_CONFIG            = 13;
my $PACKET_TYPE_WIRELESS_NETWORKS = 14;
my $PACKET_TYPE_STREAMCTL         = 15;
my $PACKET_TYPE_ENGINE       = 16;
my $PACKET_TYPE_LOG               = 17;

my $FILE_ID_MUSIC            = 64;
my $FILE_ID_FIRMWARE         = 66;

my $SENDFILE_FLAG_NONE       = 0;
my $SENDFILE_FLAG_BEGIN      = 1;
my $SENDFILE_FLAG_END        = 2;

my $MESSAGE_TYPE_ACTIVATE         = 1;
my $MESSAGE_TYPE_CHARGE_STOP      = 5;
my $MESSAGE_TYPE_BASE_FIND        = 6;
my $MESSAGE_TYPE_BASE_FIND_CANCEL = 7;

my $STREAM_ID_VIDEO               = 1;
my $STREAM_ID_AUDIO_IN            = 2;
my $STREAM_ID_AUDIO_OUT           = 3;

=head1 API

=head2 discover ( $callback )

Broadcast on the local network and find Spykee robots.

  Params : function pointer to function receiving the robot IP and
           info string
  Returns: nothing

Example

  Spyeee::discover(sub { print "Host IP: $_[0]\n"; });

=cut

sub discover_prepare {
    my $sock;
    my $senderPort = 9721;

    socket($sock, PF_INET, SOCK_DGRAM, getprotobyname('udp')) or die "socket: $!";
    setsockopt($sock, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)) or die "setsockopt: $!";
    setsockopt($sock, SOL_SOCKET, SO_BROADCAST, pack("l", 1)) or die "sockopt: $!";
    bind($sock, sockaddr_in($senderPort, INADDR_ANY)) or die "bind: $!";

    return $sock;
}

sub discover_broadcast {
    my ($sock) = @_;

    my $receiverPort = 9000;

    my $datastring = "DSCV\01";
    my $bytes = send($sock, $datastring, 0,
                     sockaddr_in($receiverPort,
                                 inet_aton('255.255.255.255'))
        );

    if (!defined($bytes)) {
        print("$!\n");
    } else {
#        print("sent $bytes bytes\n");
    }
}

sub discover_read {
    my ($sock, $hook) = @_;

    my $datastring;
    my $hispaddr = recv($sock, $datastring, 64, 0);
    if (!defined($hispaddr)) {
        print("recv failed: $!\n");
        next;
    }
    my ($port, $hisiaddr) = sockaddr_in($hispaddr);
    my $host = inet_ntoa($hisiaddr);
#        print "D: '$datastring' - $host\n";
    $hook->($host, $datastring);
}

sub discover {
    my $hook = shift;
    my $sock = discover_prepare();
    my $start = time();
    my $lastbroadcast = $start;
    my $now = time();
    while ($now - $start < 5) {
        if ($lastbroadcast + 1 < $now) {
            discover_broadcast($sock);
            $lastbroadcast = $now;
        }
        my $read_set = new IO::Select(); # create handle set for reading
        $read_set->add($sock);           # add the main socket to the set
        my ($rh_set) = IO::Select->select($read_set, undef, undef, 2);
        for my $rh (@$rh_set) {
            discover_read($sock, $hook);
        }
        $now = time();
    }
    close($sock);
    return;
}

=head2 new ( )

Create new perl object representing a robot.

Example:

  my $spykee = new Robotics::Spykee(hostname => '10.11.12.13');

=cut

sub new {
    my ($class) = shift;
    my $self = bless {
        "hostname"  => undef,
        'port'      => 9000,
        "powerlvl"  => undef,
        "socket"    => undef,
        "movespeed" => 5,
        "audiohook" => undef,
        "videohook" => undef,
        "powerhook" => undef,
        'username'  => 'admin',
        'password'  => 'admin',
        @_
    }, $class;

    my ($hostname, $port, $username, $password) =
        ($self->{hostname}, $self->{port},
         $self->{username}, $self->{password});

    print "Connecting to $hostname port $port\n";

    my $sock = new IO::Socket::INET (
        PeerAddr => $hostname,
        PeerPort => $port,
        Proto => 'tcp',
        );
    unless ($sock) {
        print STDERR "Could not create socket: $!\n";
        return undef
    }

    $self->{socket} = $sock;

    $self->sendpackage($PACKET_TYPE_AUTH_REQUEST,
                       _packstring($username) . _packstring($password));
    $self->process_packet();

    return $self;
}

sub sendpackage {
    my ($self, $type, $data) = @_;
    my $datalen = 0;
    if (defined $data) {
        $datalen = length $data;
    }
    my $sock = $self->{socket};
    my $msg = pack("a2Cn", "PK", $type, $datalen);
    $msg .= $data if defined $data;
#    print "Sending package: '$msg'\n";
    print $sock $msg;
}

sub _packstring {
    my $string = shift;
    return pack("Ca*", length $string, $string);
}

=head2 process_package ( $hook )

Read a package originating from the robot.

Example:

  sub hook { my $type = shift; }
  $spykee->process_package(\&hook);

=cut

sub process_packet {
    my ($self, $hook) = @_;
    print "Processing incoming packages.\n";
    my $sock = $self->{socket};

    my $buf;
    $sock->read($buf, $PACKET_HEADER_SIZE);
    my ($header, $type, $datalen) = unpack "a2Cn", $buf;
    my $data;
    if ($datalen) {
        $sock->read($data, $datalen);
    }
    print "Packet received: header=$header, type=$type, len=$datalen";
#    print " data='$data'" if defined $data;
    print "\n";
    if ($type == $PACKET_TYPE_AUDIO) {
        print "Audio reply received\n";
        $self->{audiohook}($datalen, $data)
            if ($self->{audiohook});
    } elsif ($type == $PACKET_TYPE_VIDEO) {
        print "Video reply (JPEG) received, size $datalen\n";
        $self->{videohook}($datalen, $data)
            if ($self->{videohook});
    } elsif ($type == $PACKET_TYPE_POWER) {
        my $powerlvl = unpack("C", $data);
        $self->{powerlvl} = $powerlvl;
        print "battery status $powerlvl\n";
        $self->{powerhook}($powerlvl)
            if ($self->{powerhook});
    } elsif ($type == $PACKET_TYPE_AUTH_REPLY) {
        print "Auth reply received\n";
    } elsif ($type == $PACKET_TYPE_STOP) {
        print "STOP message received\n";
        # Music playing just stopped
        #$self->play($FILE_ID_MUSIC);
    } elsif ($type == $PACKET_TYPE_WIRELESS_NETWORKS) {
        print "wifi network list received\n";
        my @net = split(/;/, $data);
        for (@net) {
            my ($essid, $type, $strengh) = split(/:/);
            print "  '$essid' '$type' '$strengh'\n";
        }
    } elsif ($type == $PACKET_TYPE_CONFIG) {
        print "config received\n";
        my @settings = split(/&/, $data);
        for (@settings) {
            my ($name, $value) = split(/=/, $_, 2);
            print "  '$name' = '$value'\n";
        }
    } elsif ($type == $PACKET_TYPE_LOG) {
        print "log received\n";
        my @log = split(/\n/, $data);
        for (@log) {
            print "  '$_'\n";
        }
    } else {
        print "warning: Unhandled type $type\n";
    }

    $hook->($type) if $hook;
    return 1;
}

=head2 video_set ( $enabled )

Enable or disable the video stream.

Example:

  $spykee->video_set(1);

=cut

sub video_set {
    my ($self, $enable) = @_;
    $self->sendpackage($PACKET_TYPE_STREAMCTL,
                       pack("CC", $STREAM_ID_VIDEO, $enable));
}

=head2 audio_in_set ( $enabled )

Enable or disable the audio stream from the robot.

Example:

  $spykee->audio_in_set(1);

=cut

sub audio_in_set {
    my ($self, $enable) = @_;
    $self->sendpackage($PACKET_TYPE_STREAMCTL,
                       pack("CC", $STREAM_ID_AUDIO_IN, $enable));
}

=head2 move ( $left, $right )

Set the speed on the robot belts.

Example:

  $spykee->move(100, 100);  # To drive forward

=cut

sub move {
    my ($self, $left, $right) = @_;
    $self->sendpackage($PACKET_TYPE_MOVE, pack("CC", $left, $right));
}

sub left {
    my ($self) = @_;
    $self->move(140, 110);
}

sub right {
    my ($self) = @_;
    $self->move(110, 140);
}

sub forward {
    my ($self) = @_;
    my $speed = $self->{movespeed};
    $self->move(125 - $speed, 125 - $speed);
}

sub back {
    my ($self) = @_;
    my $speed = $self->{movespeed};
    $self->move(125 + $speed, 125 + $speed);
}

sub stop {
    my ($self) = @_;
    $self->move(0,0);
}

sub activate {
    my ($self) = @_;
    $self->sendpackage($PACKET_TYPE_ENGINE, pack("C", $MESSAGE_TYPE_ACTIVATE));
}

sub charge_stop {
    my ($self) = @_;
    $self->sendpackage($PACKET_TYPE_ENGINE, pack("C", $MESSAGE_TYPE_CHARGE_STOP));
}

sub dock {
    my ($self) = @_;
    $self->sendpackage($PACKET_TYPE_ENGINE, pack("C", $MESSAGE_TYPE_BASE_FIND));
}

sub dock_cancel {
    my ($self) = @_;
    $self->sendpackage($PACKET_TYPE_ENGINE, pack("C", $MESSAGE_TYPE_BASE_FIND));
}

sub send_file {
    my ($self, $filename, $file_id) = @_;
    my $flag = $SENDFILE_FLAG_BEGIN;

    print "Sending file $filename\n";
    $| = 1;
    open(my $fh, "<", $filename);
    my $maxlen = $PACKET_DATA_SIZE_MAX - $PACKET_HEADER_SIZE;
    my $content;
    while (my $contentlen = read($fh, $content, $maxlen)) {
        if ($maxlen !=  $contentlen) {
            # End of file, set the end flag
            $flag |= $SENDFILE_FLAG_END;
        }
        $self->sendpackage($PACKET_TYPE_FILE,
                           pack("CCA*", $file_id, $flag, $content));
        if ($flag & $SENDFILE_FLAG_BEGIN) {
            print "<";
        } elsif ($flag & $SENDFILE_FLAG_END) {
            print ">";
        } else {
            print ".";
        }

        # Clear begin flag
        $flag &= ~ $SENDFILE_FLAG_BEGIN;
    }
    close($fh);
    print "\n";
}

sub send_firmware {
    my ($self, $filename) = @_;
    $self->send_file($filename, $FILE_ID_FIRMWARE);
}

=head2 send_mp3 ( $filename )

Send an MP3 file to the robot, to allow it to be played on the robot.

=cut

sub send_mp3 {
    my ($self, $filename) = @_;
    $self->send_file($filename, $FILE_ID_MUSIC);
}

sub audio_play {
    my ($self, $file_id) = @_;
    $self->sendpackage($PACKET_TYPE_PLAY, pack("C", $file_id));
}

sub audio_stop {
    my ($self) = @_;
    $self->sendpackage($PACKET_TYPE_STOP);
}

sub wireless_networks {
    my ($self) = @_;
    $self->sendpackage($PACKET_TYPE_WIRELESS_NETWORKS);
}

sub get_log {
    my ($self) = @_;
    $self->sendpackage($PACKET_TYPE_LOG);
}

sub get_config {
    my ($self) = @_;
    $self->sendpackage($PACKET_TYPE_CONFIG);
}

sub get_powerlvl {
    my ($self) = @_;
    return $self->{powerlvl};
}

1;
