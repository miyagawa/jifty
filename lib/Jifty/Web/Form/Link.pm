use warnings;
use strict;

package Jifty::Web::Form::Link;

=head1 NAME

Jifty::Web::Form::Link - Creates a state-preserving HTML link

=head1 DESCRIPTION

Describes an HTML link that may be AJAX-enabled.  Most of the
computation of this comes from L<Jifty::Web::Form::Clickable>, which
generates L<Jifty::Web::Form::Link>s.

=cut

use Moose;
has url             => qw( is rw isa Str lazy 1 default ) => sub { $ENV{PATH_INFO} };
has escape_label    => qw( is rw isa Bool default 1 );
has tooltip         => qw( is rw isa Str );
has target          => qw( is rw isa Str );
no Moose;

use base 'Jifty::Web::Form::Element';

# Since we don't inherit from Form::Field, we don't otherwise stringify
use overload '""' => sub { shift->render }, bool => sub { 1 };

=head2 accessors

Link adds C<url> and C<escape_label> to the list of possible accessors
and mutators, in addition to those offered by
L<Jifty::Web::Form::Element/accessors>.

=cut

=head2 new PARAMHASH

Creates a new L<Jifty::Web::Form::Link> object.  Possible arguments to
the C<PARAMHASH> are:

=over

=item url (optional)

The URL of the link; defaults to the current URL.

=item tooltip

Additional information about the link.

=item target

Target of the link.  Mostly useful when specified as "_blank" to open
a new window or as the name of a already existing window.

=item escape_label

HTML escape the label and tooltip? Defaults to true

=item anything from L<Jifty::Web::Form::Element>

Any parameter which L<Jifty::Web::Form::Element/new> can take.

=back

=cut


=head2 url [URL]

Gets or sets the URL that the link links to.

=cut

=head2 render

Render the string of the link, including any necessary javascript.

=cut

sub render {
    my $self = shift;

    my $label = $self->label;
    $label = Jifty->web->escape( $label )
        if ( $self->escape_label );

    my $tooltip = $self->tooltip;
    $tooltip = Jifty->web->escape( $tooltip )
        if ( $tooltip and $self->escape_label );

    Jifty->web->out(qq(<a));
    Jifty->web->out(qq( id="@{[$self->id]}"))         if $self->id;
    Jifty->web->out(qq( class="@{[$self->class]}"))   if $self->class;
    Jifty->web->out(qq( title="@{[$self->tooltip]}")) if $tooltip;
    Jifty->web->out(qq( target="@{[$self->target]}")) if $self->target;
    Jifty->web->out(qq( href="@{[$self->url]}"));
    Jifty->web->out( $self->javascript() );
    Jifty->web->out(qq(>$label</a>));
    $self->render_key_binding();

    return ('');
}

1;
