use warnings;
use strict;

package Jifty::Web::Form;

use base qw/Jifty::Object/;

use Moose;
has actions         => qw( is rw isa Any );
has printed_actions => qw( is rw isa Any );
has name            => qw( is rw isa Str );
has call            => qw( is rw isa Str );
has is_open         => qw( is rw isa Bool );
no Moose;

=head2 new ARGS

Creates a new L<Jifty::Web::Form>.  Arguments:

=over

=item name

The name given to the form.  This is mostly for naming specific forms
for testing.

=item call

All buttons in this form will act as continuation calls for the given
continuation id.

=back

=cut

sub new {
    my $class = shift;
    my $self = bless {}, ref $class ? ref $class : $class;

    my %args = (
        name => undef,
        call => undef,
        @_,
    );

    $self->_init(%args);
    return $self;
}

=head2 PRIVATE _init

Reinitialize this form.

=over

=item name

The form name

=item call

The continuation id to call

=back

=cut


sub _init {
    my $self = shift;
    my %args = (name => undef,
                call => undef,
                @_);

    $self->actions( {} ) ;
    $self->printed_actions( {} ) ;
    $self->name($args{name});
    $self->call($args{call});
}


=head2 actions

Returns a reference to a hash of L<Jifty::Action> objects in this form keyed by moniker.

If you want to add actions to this form, use L</add_action>

=cut

=head2 name [VALUE]

Gets or sets the HTML name given to the form element.

=cut

=head2 call [CONTID]

Gets or sets the continuation ID that will be called for this form.

=cut

=head2 is_open [BOOL]

This accessor returns true if Jifty is currently in the middle of rendering a form
(if it's printed a <form> but not yet printed a </form> tag.) Use this in your
components to decide whether to open a form or not if you might be called from a
template that opened the form for you.

=cut

=head2 add_action PARAMHASH

Calls L<Jifty::Web/new_action> with the paramhash given, and adds it to
the form.

=cut

sub add_action {
    my $self = shift;
    $self->register_action(Jifty->web->new_action(@_));
}



=head2 register_action ACTION

Adds C<ACTION> as an action for this form. Called so that actions'
form fields can register the action against the form they're being
used in.

=cut


sub register_action {
    my $self = shift;
    my $action = shift;
    $self->actions->{ $action->moniker } =  $action;
    return $action;
}


=head2 has_action MONIKER

If this form has an action whose monkier is C<MONIKER>, returns
it. Otherwise returns undef.

=cut

sub has_action {
    my $self    = shift;
    my $moniker = shift;
    if ( exists $self->actions->{$moniker} ) {
        return $self->actions->{$moniker};
    }
    else { return undef }

}



=head2 start

Renders the opening form tag.

=cut

sub start {
    my $self = shift;

    my %args = (@_);

    if ($self->is_open) {
        $self->log->warn("Trying to open a form when we already have one open");
    }

    for (keys %args) {
        if ( $self->can($_) ) {
            $self->$_($args{$_});
        } else {
			my (undef, $template, $line) = caller;
            $self->log->warn("Unknown parameter to Jifty->web->form->start: $_ in $template line $line");
        }
    }

    my $form_start = qq!<form method="post" action="$ENV{PATH_INFO}"!;
    $form_start   .= qq! name="@{[ $self->name ]}"! if defined $self->name;
    $form_start   .= qq! enctype="multipart/form-data" >\n!;
    Jifty->web->out($form_start);
    $self->is_open(1);
    '';
}

=head2 submit MESSAGE, [PARAMETERS]

Renders a submit button with the text MESSAGE on it (which will be
HTML escaped).  Returns the empty string (for ease of use in
interpolation).  Any extra PARAMETERS are passed to
L<Jifty::Web::Form::Field::Button>'s constructor.

=cut

sub submit {
    my $self = shift;

    my $button = Jifty::Web::Form::Clickable->new(submit => undef, @_)->generate;
    Jifty->web->out(qq{<div class="submit_button">});
    $button->render_widget;
    Jifty->web->out(qq{</div>});

    return '';
}

=head2 end

Renders the closing form tag (including rendering errors for and
registering all of the actions)  After doing this, it resets its
internal state such that L</start> may be called again.

=cut

sub end {
    my $self = shift;

    unless ($self->is_open) {
        $self->log->warn("Trying to close a form when we don't have one open");
    }
    Jifty->web->out( qq!<div class="hidden">\n! );

    $self->_print_registered_actions();
    $self->_preserve_state_variables();
    $self->_preserve_continuations();

    Jifty->web->out( qq!</div>\n! );

    Jifty->web->out( qq!</form>\n! );
    $self->is_open(0);
    # Clear out all the registered actions and the name
    $self->_init();

    '';
}


=head2 print_action_registration MONIKER

Print out the action registration goo for this action _right now_, unless we've already done so.

=cut


sub print_action_registration {
    my $self = shift;
    my $moniker = shift;


    my $action = $self->has_action($moniker);
    return unless ($action);
    return if exists $self->printed_actions->{$moniker};
    $self->printed_actions->{$moniker} = 1;

    $action->register();

}


# At the point this is called, it should only include actions we're
# registering that have no form fields and haven't been explicitly
# registered.
sub _print_registered_actions {
    my $self = shift;
    for my $a ( keys %{ $self->actions } ) {
        $self->print_action_registration($a);
    }
}

sub _preserve_state_variables {
    my $self = shift;

    my %vars = Jifty->web->state_variables;
    for (keys %vars) {
        Jifty->web->out( qq{<input type="hidden" name="}
                . $_
                . qq{" value="}
                . $vars{$_}
                . qq{" />\n} );
    }
}

sub _preserve_continuations {
    my $self = shift;

    if ($self->call) {
        Jifty->web->out( qq{<input type="hidden" name="J:CALL" value="}
                                . (ref $self->call ? $self->call->id : $self->call)
                                . qq{" />});
    } elsif (Jifty->web->request->continuation) {
        Jifty->web->out( qq{<input type="hidden" name="J:C" value="}
                                . Jifty->web->request->continuation->id
                                . qq{" />});
    }

}

=head2 next_page PARAMHASH

Set the page this form should go to on success.  This simply creates a
L<Jifty::Action::Redirect> action; any parameters in the C<PARAMHASH>
are passed as arguments to the L<Jifty::Action::Redirect> action.

Returns an empty string so it can be included in forms

=cut

sub next_page {
    my $self = shift;

    $self->add_action(class => "Jifty::Action::Redirect", moniker => "next_page", arguments => {@_});
    return '';
}

1;
