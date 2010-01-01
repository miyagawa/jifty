use warnings;
use strict;

package Jifty::Web::Session;
use base qw/Jifty::Object/;
use CGI::Simple::Cookie ();
use DateTime    ();
use Storable    ();
$Storable::Deparse    = 1;
$Storable::Eval       = 1;
$Storable::forgive_me = 1;

=head1 NAME

Jifty::Web::Session - A Jifty session handler

=head1 SYNOPSIS

In your F<etc/config.yml> (optional):

  framework:
    Web:
      # The default ($PORT is replaced by the port the app is running on)
      SessionCookieName: JIFTY_SID_$PORT

=head2 new

Returns a new, empty session.

=cut

sub new {
    my $class = shift;

    my $session_class = Jifty->config->framework('Web')->{'SessionClass'};
    my $cookie_name = Jifty->config->framework('Web')->{'SessionCookieName'};
    if ( $session_class and $class ne $session_class ) {
        Jifty::Util->require($session_class);
        return $session_class->new(@_);
    } else {
        return bless { _cookie_name => $cookie_name }, $class;
    }
}

=head2 id

Returns the session's id if it has been loaded, or C<undef> otherwise.

=cut

sub id {
    my $self = shift;
    return $self->loaded ? $self->_session->session_id : undef;
}

=head2 load [ID]

Load up the current session from the given C<ID>, or the appropriate
cookie (see L</cookie_name>) otherwise.  If both of those fail,
creates a session in the database.

=cut

sub load {
    my $self       = shift;
    my $session_id = shift;

    $session_id ||= $self->_get_session_id_from_client();

    my $session = Jifty::Model::Session->new;
    $session->load_by_cols(
        session_id => $session_id,
        key_type   => "session"
    ) if $session_id;

    $session->create( key_type => "session" ) unless $session->id;
    $self->_session($session);
}

=head2 load_by_kv key => value 

Load up the current session from the given (key, value) pair. If no matching
session could be found, it will create a new session with the key, value set.
Be sure that what you're loading by is unique. If you're loading a session
based on, say, a timestamp, then you're asking for trouble.

=cut

sub load_by_kv {
    my $self = shift;
    my $k    = shift;
    my $v    = shift;

# XXX TODO: we store this data in a storable. so we now want to match on the storable version
# It would be so nice if Jifty::DBI could do this for us.
    my $encoded = Storable::nfreeze( \$v );

    my $session = Jifty::Model::Session->new;
    $session->load_by_cols(
        key_type => 'key',
        data_key => $k,
        value    => $encoded,
    );
    my $session_id = $session->session_id;

    # XXX: if $session_id is undef, then bad things happen. This *can* happen.

    $self->load($session_id);
    $self->set( $k => $v ) if !$session_id;
}

sub _get_session_id_from_client {
    my $self        = shift;
    my %cookies     = Jifty->web->request ? CGI::Simple::Cookie->parse(Jifty->web->request->env->{HTTP_COOKIE}) : ();
    my $cookie_name = $self->cookie_name;
    my $session_id
        = $cookies{$cookie_name} ? $cookies{$cookie_name}->value() : undef;
    return $session_id;
}

=head2 unload

Flush the session, and leaves the session object blank.

=cut

sub unload {
    my $self = shift;

    return unless $self->loaded;
    $self->_session(undef);
}

=head2 loaded

Returns true if the session has already been loaded.

=cut

sub loaded {
    my $self = shift;
    return $self->_session;
}

sub _session {
    my $self = shift;
    $self->{'_session'} = shift if (@_);
    return ( $self->{'_session'} );
}

=head2 get KEY [TYPE]

Returns the value for C<KEY> for the current user's session.  C<TYPE>,
which defaults to "key", allows accessing of other namespaces in the
session, including "metadata" and "continuation".

=cut

sub get {
    my $self     = shift;
    my $key      = shift;
    my $key_type = shift || "key";

    return undef unless $self->loaded;

    my $setting = Jifty::Model::Session->new;
    $setting->load_by_cols(
        session_id => $self->id,
        key_type   => $key_type,
        data_key   => $key
    );
    return $setting->value;

}

=head2 set KEY => VALUE, [TYPE]

Sets the value C<VALUE> for C<KEY> for the session.  C<TYPE>, which
defaults to "key", allows values to be set in other namespaces,
including "metadata" and "continuation". C<VALUE> can be an arbitrary
perl data structue -- C<Jifty::Web::Session> will serialize it for
you.

=cut

sub set {
    my $self     = shift;
    my $key      = shift;
    my $value    = shift;
    my $key_type = shift || "key";

    return undef unless $self->loaded;
    $self->_session->set_updated( DateTime->now );

    my $setting = Jifty::Model::Session->new;
    $setting->load_by_cols(
        session_id => $self->id,
        key_type   => $key_type,
        data_key   => $key
    );
    if ( $setting->id ) {
        $setting->set_value($value);
    } else {
        $setting->create(
            session_id => $self->id,
            key_type   => $key_type,
            data_key   => $key,
            value      => $value
        );
    }

}

=head2 remove KEY, [TYPE]

Remove key C<KEY> from the cache.  C<TYPE> defaults to "key".

=cut

sub remove {
    my $self     = shift;
    my $key      = shift;
    my $key_type = shift || "key";

    return undef unless $self->loaded;
    $self->_session->set_updated( DateTime->now );

    my $setting = Jifty::Model::Session->new;
    $setting->load_by_cols(
        session_id => $self->id,
        key_type   => $key_type,
        data_key   => $key
    );
    $setting->delete if $setting->id;
}

=head2 remove_all

Removes the session from the database entirely.

=cut

sub remove_all {
    my $self = shift;
    return unless $self->loaded;
    my $settings = Jifty::Model::SessionCollection->new;
    $settings->limit( column => "session_id", value => $self->id );
    $_->delete while $_ = $settings->next;
    $self->unload;
}

=head2 set_continuation ID CONT

Stores a continuation in the session.

=cut

sub set_continuation {
    my $self = shift;
    $self->set( @_, "continuation" );
}

=head2 get_continuation ID

Pulls a continuation from the current session. Expects a continuation
C<ID>.

=cut

sub get_continuation {
    my $self = shift;
    $self->get( @_, "continuation" );

}

=head2 remove_continuation ID

Removes a continuation with id C<ID> from the store.

=cut

sub remove_continuation {
    my $self = shift;
    $self->remove( @_, "continuation" );
}

=head2 continuations

Return a hash of all the continuations in this session, keyed by the
continuations' C<id>.

=cut

sub continuations {
    my $self = shift;

    return () unless $self->loaded;

    my $conts = Jifty::Model::SessionCollection->new;
    $conts->limit( column => "key_type",   value => "continuation" );
    $conts->limit( column => "session_id", value => $self->id );

    my %continuations;
    $continuations{ $_->data_key } = $_->value while $_ = $conts->next;
    return %continuations;
}

=head2 set_cookie

Sets the session cookie.

=cut

sub set_cookie {
    my $self = shift;

    # never send a cookie with cached content. misbehaving proxies cause
    # terrific problems
    return if Jifty->web->response->header('Expires');

    $self->load unless $self->loaded;

    my $cookie_name = $self->cookie_name;
    my %cookies     = Jifty->web->request ? CGI::Simple::Cookie->parse(Jifty->web->request->env->{HTTP_COOKIE}) : ();

    my $cookie      = CGI::Simple::Cookie->new(
        -name    => $cookie_name,
        -value   => $self->id,
        -expires => $self->expires,
    );

    if ( not $cookies{$cookie_name}
        or ( $cookies{$cookie_name} ne $cookie->as_string ) )
    {
        Jifty->web->response->cookies->{$cookie->name} = $cookie;
    }
}

=head2 cookie_name

Returns the current session's cookie_name -- it is the same for all
users, but varies according to the port the server is running on.

=cut

sub cookie_name {
    my $self        = shift;
    my $cookie_name = $self->{'_cookie_name'};
    my $port        = ( $ENV{'SERVER_PORT'} || 'NOPORT' );
    $cookie_name =~ s/\$PORT/$port/g;
    return ($cookie_name);
}

=head2 expires [VALUE]

Get or set the session's expiration date, in a format expected by
Cache::Cache.

=cut

sub expires {
    my $self = shift;
    $self->set( 'expires' => shift, "metadata" ) if @_;
    return ( $self->get( 'expires', "metadata" ) );
}

1;
