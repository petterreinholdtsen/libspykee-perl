/****************************************************************************
** ui.h extension file, included from the uic-generated form implementation.
**
** If you want to add, delete, or rename functions or slots, use
** Qt Designer to update this file, preserving your code.
**
** You should not define a constructor or destructor in this file.
** Instead, write your code in functions called init() and destroy().
** These will automatically be called by the form's constructor and
** destructor.
*****************************************************************************/


void guidemo::forward()
{
    this->{spykee}->forward() if exists this->{spykee};
}


void guidemo::stop()
{
    this->{spykee}->stop() if exists this->{spykee};
}


void guidemo::back()
{
    this->{spykee}->back() if exists this->{spykee};
}


void guidemo::left()
{
    this->{spykee}->left() if exists this->{spykee};
}


void guidemo::right()
{
    this->{spykee}->right() if exists this->{spykee};
}


void guidemo::robotconnect()
{
    my %robot;
    Robotics::Spykee::discover(sub {$robot{$_[0]} = $_[1]});
    my $host = (keys %robot)[0];
    print "Trying to connect to $host " . $robot{$host} . "\n";
    this->{spykee} = Robotics::Spykee->new(hostname => $host,
                                 videohook => \&videohook,
                                 powerhook => \&powerhook);

    # Do not fail if unable to find robot
    if (this->{spykee}) {
        # Add input handler for socket IO.
        this->{notifier} =
            Qt::SocketNotifier(fileno(this->{spykee}->{socket}),
                               Qt::SocketNotifier::Read());
        this->connect(this->{notifier}, SIGNAL "activated(int)",
                      SLOT "processMessage(int)");
        this->{notifier}->setEnabled(1);
    }
}


void guidemo::robotDock()
{
    this->{spykee}->dock() if exists this->{spykee};
}


void guidemo::robotUndock()
{
    if (exists this->{spykee}) {
        this->{spykee}->dock_cancel();
        this->{spykee}->activate();
        this->{spykee}->charge_stop();
    }
}

void guidemo::processMessage(int)
{
    this->{spykee}->process_packet() if exists this->{spykee};
}

void guidemo::videohook(int, char*)
{
    my ($datasize, $data) = @_;
    my $qp = Qt::Pixmap();
    if ($qp->loadFromData($data, length $data, "JPEG")) {
        pixmapLabel1->setPixmap( $qp );
	pixmapLabel1->setScaledContents( 1 );
	pixmapLabel1->show();
    } else {
        print "error loading JPEG image\n";
    }
}


void guidemo::powerhook(int)
{
    my ($powerlvl) = @_;
    powerlevel->setProgress($powerlvl);
}

void guidemo::videoenable(bool)
{
    my $enable = shift;
    this->{spykee}->video_set($enable) if exists this->{spykee};
}
