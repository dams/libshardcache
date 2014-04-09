package Shardcache::Client::Fast;

use v5.10;
use strict;
use warnings;
use Carp;

require Exporter;
use AutoLoader;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Shardcache::Client::Fast ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	shardcache_client_create
	shardcache_client_del
	shardcache_client_destroy
	shardcache_client_evict
	shardcache_client_get
	shardcache_client_get_async
	shardcache_client_touch
	shardcache_client_exists
	shardcache_client_set
	shardcache_client_add
        shardcache_client_check
        shardcache_client_index
        shardcache_client_stats
        shardcache_client_errno
        shardcache_client_errstr
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.07';

sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.

    my $constname;
    our $AUTOLOAD;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    croak "&Shardcache::Client::Fast::constant not defined" if $constname eq 'constant';
    my ($error, $val) = constant($constname);
    if ($error) { croak $error; }
    {
	no strict 'refs';
	# Fixed between 5.005_53 and 5.005_61
#XXX	if ($] >= 5.00561) {
#XXX	    *$AUTOLOAD = sub () { $val };
#XXX	}
#XXX	else {
	    *$AUTOLOAD = sub { $val };
#XXX	}
    }
    goto &$AUTOLOAD;
}

require XSLoader;
XSLoader::load('Shardcache::Client::Fast', $VERSION);

# Preloaded methods go here.

# Autoload methods go after =cut, and are processed by the autosplit program.

sub new {
    my ($class, $nodes, $secret) = @_;

    my $self = {
        _nodes  => [],
        (defined $secret ? (_secret => $secret) : ()),
    };

    if (ref($nodes) && ref($nodes) eq "ARRAY") {
        foreach my $h (@$nodes) {
            my $label;
            my $addr;
            if (ref($h) && ref($h) eq "ARRAY") {
                $label = $h->[0];
                $addr = $h->[1];
            } else {
                if ($h !~ /[a-zA-Z0-9_\.]+:[a-zA-Z0-9_\.]+(:[0-9]+)?/) {
                    die "Invalid host string $h";
                }
                ($label, $addr, my $port) = split(':', $h);
                $addr = join(':', $addr, $port);
            }
            push(@{$self->{_nodes}}, [ $label, $addr ]);
        }
    } else {
        if ($nodes !~ /[a-zA-Z0-9_\.]+:[a-zA-Z0-9_\.]+(:[0-9]+)?/) {
            die "Invalid host string $nodes";
        }
        my ($label, $addr, $port) = split(':', $nodes);
        if ($port) {
            $addr = join(':', $addr, $port);
        } else {
            $label = join(':', $addr,$port);
            $addr = $label;
        }
        push(@{$self->{_nodes}}, [ $label, $addr ]);
    }

    $self->{_client} = shardcache_client_create($self->{_nodes}, $secret // '');

    return undef unless ($self->{_client});

    bless $self, $class;

    return $self;
}

sub get {
    my ($self, $key) = @_;
    my $val =  shardcache_client_get($self->{_client}, $key);
    if ($val) {
        undef($self->{_errstr});
        $self->{_errno} = 0;
    } else {
        $self->{_errstr} = shardcache_client_errstr($self->{_client});
        $self->{_errno} = shardcache_client_errno($self->{_client});
    }
    return $val;
}

sub offset {
    my ($self, $key, $offset, $length) = @_;
    my $val =  shardcache_client_offset($self->{_client}, $key, $offset, $length);
    if ($val) {
        undef($self->{_errstr});
        $self->{_errno} = 0;
    } else {
        $self->{_errstr} = shardcache_client_errstr($self->{_client});
        $self->{_errno} = shardcache_client_errno($self->{_client});
    }
    return $val;
}

sub get_async {
    my ($self, $key, $cb, $priv) = @_;
    return shardcache_client_get_async($self->{_client}, $key, $cb, $priv);
}

sub set {
    my ($self, $key, $value, $expire) = @_;
    $expire = 0 unless defined $expire;
    my $ret = shardcache_client_set($self->{_client}, $key, $value, $expire);
    if ($ret == 0) {
        undef($self->{_errstr});
        $self->{_errno} = 0;
    } else {
        $self->{_errstr} = shardcache_client_errstr($self->{_client});
        $self->{_errno} = shardcache_client_errno($self->{_client});
    }
    return ($ret == 0);
}

sub add {
    my ($self, $key, $value, $expire) = @_;
    $expire = 0 unless defined $expire;
    my $ret = shardcache_client_add($self->{_client}, $key, $value, $expire);
    if ($ret == 0) {
        undef($self->{_errstr});
        $self->{_errno} = 0;
    } else {
        $self->{_errstr} = shardcache_client_errstr($self->{_client});
        $self->{_errno} = shardcache_client_errno($self->{_client});
    }
    return ($ret == 0);
}

sub exists {
    my ($self, $key) = @_;
    my $ret = shardcache_client_exists($self->{_client}, $key);
    if ($ret == 1 || $ret == 0) {
        undef($self->{_errstr});
        $self->{_errno} = 0;
    } else {
        $self->{_errstr} = shardcache_client_errstr($self->{_client});
        $self->{_errno} = shardcache_client_errno($self->{_client});
    }
    return $ret;
}

sub touch {
    my ($self, $key) = @_;
    my $ret = shardcache_client_touch($self->{_client}, $key);
    if ($ret == 0) {
        undef($self->{_errstr});
        $self->{_errno} = 0;
    } else {
        $self->{_errstr} = shardcache_client_errstr($self->{_client});
        $self->{_errno} = shardcache_client_errno($self->{_client});
    }
    return ($ret == 0);
}

sub del {
    my ($self, $key) = @_;
    my $ret = shardcache_client_del($self->{_client}, $key);
    if ($ret == 0) {
        undef($self->{_errstr});
        $self->{_errno} = 0;
    } else {
        $self->{_errstr} = shardcache_client_errstr($self->{_client});
        $self->{_errno} = shardcache_client_errno($self->{_client});
    }
    return ($ret == 0);
}

sub evict {
    my ($self, $key) = @_;
    my $ret = shardcache_client_evict($self->{_client}, $key);
    if ($ret == 0) {
        undef($self->{_errstr});
        $self->{_errno} = 0;
    } else {
        $self->{_errstr} = shardcache_client_errstr($self->{_client});
        $self->{_errno} = shardcache_client_errno($self->{_client});
    }
    return ($ret == 0);
}

sub stats {
    my ($self, $node) = @_;

    if ($node) {
        return shardcache_client_stats($self->{_client}, $node);
    }

    my $out;
    foreach my $node (@{$self->{_nodes}}) {
        $out .= shardcache_client_stats($self->{_client}, $node->[0]);
        $out .= "\n";
    }
    return $out;
}

sub check {
    my ($self, $node) = @_;
    return unless $node;
    return (shardcache_client_check($self->{_client}, $node) == 0);
}

sub index {
    my ($self, $node) = @_;
    if ($node) {
        return shardcache_client_index($self->{_client}, $node);
    }

    my $out;
    foreach my $node (@{$self->{_nodes}}) {
         my $index = shardcache_client_index($self->{_client}, $node->[0]);
         if ($index) {
             %$out =  { %$out, %$index };
         } else {
             # TODO - Error messages
         }
    }
    return $out;
}

sub get_multi {
    my ($self, $keys) = @_;
    my $res = shardcache_client_get_multi($self->{_client}, $keys);
    wantarray ? @$res : $res;
}

sub set_multi {
    my ($self, $pairs) = @_;
    my $res = shardcache_client_set_multi($self->{_client}, $pairs);
    wantarray ? %$res : $res;
}

sub errno {
    my $self = shift;
    return $self->{_errno};
}

sub errstr {
    my $self = shift;
    return $self->{_errstr};
}

sub DESTROY {
    my $self = shift;
    shardcache_client_destroy($self->{_client})
        if ($self->{_client})
}


1;
__END__

=head1 NAME

Shardcache::Client::Fast - Perl extension for the client part of libshardcache

=head1 SYNOPSIS

  use Shardcache::Client::Fast;
  @hosts = ("peer1:localhost:4444", "peer2:localhost:4445", "peer3:localhost:4446" );
  $secret = "some_secret";
  $c = Shardcache::Client::Fast->new(\@hosts, $secret);

  # Set a new value for key "key"
  $rc = $c->set("key", "value");
  if ($rc != 0) {
    die "Error setting key 'key' : " . $c->errstr;
  }

  # Read the value back
  $v = $c->get("key");
  if (!$v && $c->errno) {
    die "Error getting value for key 'key' : " . $c->errstr;
  }

  # set the key "key2" and make it expire in 60 seconds
  $c->set("key2", "value2", 60);

  # evict "key"
  $c->evict("key");

  # remove "key2" prematurely
  $c->del("key2");

  
  # check if "peer3" is alive
  if ($c->check("peer3") != 0) {
    warn "peer3 is not responding";
  }

  # get the index of keys existing on "peer2"
  $index = $c->index("peer2");

=head1 DESCRIPTION

Perl bindings to libshardcache-client. This library is a replacement for the pure-perl
Sharcache::Client allowing faster access to shardcache nodes by using libshardcache directly
instead of reimplementing the protocol and handling connections on the perl side.

=head2 EXPORT

None by default.

=head1 METHODS

=over 4

=item * new ( %params )

=back

=head3 REQUIRED PARAMS

=over 4

=item me

    A 'address:port' string describing the current node

=item storage

    A valid Shardcache::Storage subclass, implementing the underlying storage

=back

=head3 OPTIONAL PARAMS

=over

=item nodes

    An arrayref containing the nodes in our shardcache 'cloud'

=item secret

    A secret used to compute the signature used for internal communication.
    If not specified the string 'default' will be used 


=back

=over 4

=item * get ( $key )

    Get the value for $key. 
    If found in the cache it will be returned immediately, 
    if this node is responsible for $key, the underlying storage will be queried for the value,
    otherwise a request to the responsible node in the shardcache 'cloud' will be done to obtain the value
    (and the local cache will be populated)

=item * get_async ( $key, $coderef, [ $priv ] )

    Get the value for $key asynchronously.

    This function will block and call the provided callback as soon 
    as a chunk of data is read from the node.
    The control will be returned to the caller when there is no
    more data to read or an error occurred

    $coderef must be a reference to a perl SUB which will get as arguments
    the tuple : ($node, $key, $data, $priv)
    $priv will be the same scalar value passed to get_async() as last argument

    If the $coderef, called at each chunk of data being received, returns a 
    NON-TRUE value the fetch will be interrupted and the coderef won't be called
    anymore.
    Returning a TRUE value will make it go ahead until completed.

=item * exists ( $key )

    Check existence of the key on the node responsible for it.
    Returns 1 if the key exists, 0 if doesn't exist, -1 on errors

=item * touch ( $key )

    For loading of a key into the cache if not loaded already,
    otherwise updates the loaded-timestamp for the cached key.

    Returns 0 on success, -1 on errors.

=item * set ( $key, $value, [ $expire ] )

    Set a new value for $key in the underlying storage.

=item * add ( $key, $value, [ $expire ] )

    Set a new value for $key in the underlying storage if it doesn't exists.
    Returns 0 if successfully stored, 1 if already existsing, -1 in case of errors.

=item * del ( $key )

    Remove the value associated to $key from the underlying storage (note the cache of all nodes will be evicted as well).

=item * evict ( $key )

    Evict the value associated to $key from the cache (note this will not remove the value from the underlying storage).

=item * stats ( [ $node ] )

    Retrieve the stats for a given node (or all nodes if none is provided as parameter).

=item * index ( [ $node ] )

    Retrieve the index for a given node (or all nodes if none is provided as parameter).

=item * check ( $node )

    Checks the status of a given node (or all nodes if none is provided as parameter).

=item * get_multi ( @$keys )

    Get multiple keys at once. The @$keys parameter is expected to be an ARRAYREF containing the keys to retrieve.
    Returns an arrayref containing the values for the requested keys. Values are stored at the same index of the
    corresponding key in the input array. Empty or unretrieved values will be returned as undef.

    Note that multi commands are not all‐or‐nothing, some operations may succeed, while others may fail.

=item * set_multi ( %$pairs )

    Get multiple keys at once. The %$pairs parameter is expected to be an HASHREF containing the key/value pairs to set.
    Returns an hashref containing the same keys of the input hashref as keys and the status of the operation as values
    (1 if successfully set, 0 otherwise).

    Note that multi commands are not all‐or‐nothing, some operations may succeed, while others may fail.

=back

=head2 Exportable functions

  shardcache_client_t *shardcache_client_create(shardcache_node_t *nodes, int num_nodes, char *auth)
  int shardcache_client_del(shardcache_client_t *c, void *key, size_t klen)
  void shardcache_client_destroy(shardcache_client_t *c)
  int shardcache_client_evict(shardcache_client_t *c, void *key, size_t klen)
  size_t shardcache_client_get(shardcache_client_t *c, void *key, size_t klen, void **data)
  int shardcache_get_async(shardcache_t *cache, void *key, size_t klen, shardcache_get_async_callback_t cb, void *priv);
  int shardcache_client_exists(shardcache_client_t *c, void *key, size_t klen)
  int shardcache_client_touch(shardcache_client_t *c, void *key, size_t klen)
  int shardcache_client_set(shardcache_client_t *c, void *key, size_t klen, void *data, size_t dlen, uint32_t expire)
  int shardcache_client_add(shardcache_client_t *c, void *key, size_t klen)
  int shardcache_client_stats(shardcache_client_t *c, char *node, char **buf, size_t *len);
  int shardcache_client_check(shardcache_client_t *c, char *node);
  shardcache_storage_index_t *shardcache_client_index(shardcache_client_t *c, char *node);
  int shardcache_client_errno(shardcache_client_t *c)
  char *shardcache_client_errstr(shardcache_client_t *c)

=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

xant, E<lt>xant@xant.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by xant

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.12.4 or,
at your option, any later version of Perl 5 you may have available.


=cut
