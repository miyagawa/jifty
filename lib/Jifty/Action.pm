use warnings;
use strict;

package Jifty::Action;

=head1 NAME

Jifty::Action - The ability to Do Things in the framework

=head1 SYNOPSIS

    package MyApp::Action::Foo;
    use Jifty::Param::Schema;
    use Jifty::Action schema {

    param bar =>
        type is 'checkbox',
        label is 'Want Bar?',
        hints is 'Bar is this cool thing that you really want.',
        default is 0;

    };
  
    sub take_action {
        ...
    }
  
  1;

=head1 DESCRIPTION

C<Jifty::Action> is the superclass for all actions in Jifty.
Action classes form the meat of the L<Jifty> framework; they
control how form elements interact with the underlying model.

See also L<Jifty::Action::Record> for data-oriented actions, 
L<Jifty::Result> for how to return values from actions.

See L<Jifty::Param::Schema> for more details on the declarative 
syntax.

See L<Jifty::Manual::Actions> for examples of using actions.

=cut


use base qw/Jifty::Object Class::Accessor::Fast Class::Data::Inheritable/;

__PACKAGE__->mk_accessors(qw(moniker argument_values values_from_request order result sticky_on_success sticky_on_failure));
__PACKAGE__->mk_classdata(qw/PARAMS/);

=head1 COMMON METHODS

These common methods are designed to 

=head2 new 

Construct a new action.  Subclasses who need do custom initialization
should start with:

    my $class = shift; my $self = $class->SUPER::new(@_)

B<Do not call this yourself>; always go through C<<
Jifty->web->new_action >>!  The arguments that this will be
called with include:

=over

=item moniker

The L<moniker|Jifty::Manual::Glossary/moniker> of the action.  Defaults to an
autogenerated moniker.

=item order

An integer that determines the ordering of the action's execution.
Lower numbers occur before higher numbers.  Defaults to 0.

=item arguments

A hash reference of default values for the
L<arguments|Jifty::Manual::Glossary/argument> of the action.  Defaults to
none.

=item sticky_on_failure

A boolean value that determines if the form fields are
L<sticky|Jifty::Manual::Glossary/sticky> when the action fails.  Defaults to
true.

=item sticky_on_success

A boolean value that determines if the form fields are
L<sticky|Jifty::Manual::Glossary/sticky> when the action succeeds.  Defaults
to false.

=begin private

=item request_arguments

A hashref of arguments passed in as part of the
L<Jifty::Request>. Internal use only.

=end private

=back

=cut

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    my %args = (
        order      => undef,
        arguments  => {},
        request_arguments => {},
        sticky_on_success => 0,
        sticky_on_failure => 1,
        current_user => undef,
        @_);

    if ($args{'current_user'}) {
        $self->current_user($args{current_user});
    } else {
        $self->_get_current_user();
    }

    if ($args{'moniker'}) {
        $self->moniker($args{'moniker'});
    } else {
        $self->moniker($self->_generate_moniker);
    }
    $self->order($args{'order'});

    $self->argument_values( { %{ $args{'request_arguments' } }, %{ $args{'arguments'} } } );

    # Keep track of whether arguments came from the request, or were
    # programmatically set elsewhere
    $self->values_from_request({});
    $self->values_from_request->{$_} = 1 for keys %{ $args{'request_arguments' } };
    $self->values_from_request->{$_} = 0 for keys %{ $args{'arguments' } };
    
    $self->result(Jifty->web->response->result($self->moniker) || Jifty::Result->new);
    $self->result->action_class(ref($self));

    $self->sticky_on_success($args{sticky_on_success});
    $self->sticky_on_failure($args{sticky_on_failure});

    return $self;
}

=head2 _generate_moniker 

Construct a moniker for a new (or soon-to-be-constructed) action that did not have
an explicit moniker specified.  The algorithm is simple: We snapshot the call stack,
prefix it with the action class, and then append it with an per-request autoincrement
counter in case the same class/stack is encountered twice, which can happen if the
programmer placed a C<new_action> call inside a loop.

Monikers generated this way are guaranteed to work across requests.

=cut

sub _generate_moniker {
    my $self = shift;

    use Digest::MD5 qw(md5_hex);
    my $frame = 1;
    my @stack = (ref($self) || $self);
    while (my ($pkg, $filename, $line) = caller($frame++)) {
        push @stack, $pkg, $filename, $line;
    }

    # Increment the per-request moniker digest counter, for the case of looped action generation
    my $digest = md5_hex("@stack");
    # We should always have a stash. but if we don't, fake something up
    # (some hiveminder tests create actions outside of a Jifty::Web)
    my $serial = Jifty->handler->stash ? ++(Jifty->handler->stash->{monikers}{$digest}) : rand();
    my $moniker = "auto-$digest-$serial";
    $self->log->debug("Generating moniker $moniker from stack for $self");
    return $moniker;
}


=head2 arguments

B<Note>: this API is now deprecated in favour of the declarative syntax
offered by L<Jifty::Param::Schema>.

This method, along with L</take_action>, is the most commonly
overridden method.  It should return a hash which describes the
L<arguments|Jifty::Manual::Glossary/argument> this action takes:

  {
    argument_name    => {label => "properties go in this hash"},
    another_argument => {mandatory => 1}
  }

Each argument listed in the hash will be turned into a
L<Jifty::Web::Form::Field> object.  For each argument, the hash that
describes it is used to set up the L<Jifty::Web::Form::Field> object by
calling the keys as methods with the values as arguments.  That is, in
the above example, Jifty will run code similar to the following:

  # For 'argument_name'
  $f = Jifty::Web::Form::Field->new;
  $f->name( "argument_name" );
  $f->label( "Properties go in this hash" );

If an action has parameters that B<must> be passed to it to execute,
these should have the L<constructor|Jifty::Manual::Glossary/constructor>
property set.  This is separate from the
L<mandatory|Jifty::Manual::Glossary/mandatory> property, which deal with
requiring that the user enter a value for that field.


=cut

sub arguments {
    my  $self= shift;
    return($self->PARAMS || {});
}

=head2 run

This routine, unsurprisingly, actually runs the action.

If the result of the action is currently a success (validation did not
fail), C<run> calls L</take_action>, and finally L</cleanup>.

If you're writing your own actions, you probably want to override
C<take_action> instead.

=cut

sub run {
    my $self = shift;
    $self->log->debug("Running action ".ref($self) . " " .$self->moniker);
    unless ($self->result->success) {
        $self->log->debug("Not taking action, as it doesn't validate");

        # dump field warnings and errors to debug log
        foreach my $what (qw/warnings errors/) {
            my $f = "field_" . $what;
            my @r =
                map {
                    $_ . ": " . $self->result->{$f}->{$_}
                } grep { $self->result->{$f}->{$_} }
                    keys %{ $self->result->{$f} };
            $self->log->debug("Action result $what:\n\t", join("\n\t", @r)) if (@r);
        }

        return;
    }
    $self->log->debug("Taking action ".ref($self) . " " .$self->moniker);
    my $ret = $self->take_action;
    $self->log->debug("Result: ".(defined $ret ? $ret : "(undef)"));
    
    $self->cleanup;
}

=head2 validate


Checks authorization with L</check_authorization>, calls C</setup>,
canonicalizes and validates each argument that was submitted, but
doesn't actually call L</take_action>.

The outcome of all of this is stored on the L</result> of the action.

=cut

sub validate {
    my $self = shift;
    $self->check_authorization || return;
    $self->setup || return;
    $self->_canonicalize_arguments;
    $self->_validate_arguments;
}

=head2 check_authorization

Returns true if whoever invoked this action is authorized to perform
this action. 

By default, always returns true.

=cut

sub check_authorization { 1; }


=head2 setup

C<setup> is expected to return a true value, or
L</run> will skip all other actions.

By default, does nothing.

=cut

sub setup { 1; }


=head2 take_action

Do whatever the action is supposed to do.  This and
L</arguments> are the most commonly overridden methods.

By default, does nothing.

The return value from this method is NOT returned. (Instead, you
should be using the L</result> object to store a result).

=cut

sub take_action { 1; }


=head2 cleanup

Perform any action-specific cleanup.  By default, does nothing.

Runs after L</take_action> -- whether or not L</take_action> returns success.

=cut

sub cleanup { 1; }

=head2 moniker

Returns the L<moniker|Jifty::Manual::Glossary/moniker> for this action.

=head2 argument_value ARGUMENT [VALUE]

Returns the value from the argument with the given name, for this
action.  If I<VALUE> is provided, sets the value.

=cut

sub argument_value {
    my $self = shift;
    my $arg = shift;

    if(@_) {
        $self->values_from_request->{$arg} = 0;
        $self->argument_values->{$arg} = shift;
    }
    return $self->argument_values->{$arg};
}


=head2 has_argument ARGUMENT

Returns true if the action has been provided with an value for the
given argument, including a default_value, and false if none was ever
passed in.

=cut

sub has_argument {
    my $self = shift;
    my $arg = shift;

    return exists $self->argument_values->{$arg};
}


=head2 form_field ARGUMENT

Returns a L<Jifty::Web::Form::Field> object for this argument.  If
there is no entry in the L</arguments> hash that matches the given
C<ARGUMENT>, returns C<undef>.

=cut


sub form_field {
    my $self = shift;
    my $arg_name = shift;

    my $mode = $self->arguments->{$arg_name}{'render_mode'};
    $mode = 'update' unless $mode && $mode eq 'read';

    $self->_form_widget( argument => $arg_name,
                         render_mode => $mode,
                         @_);
}


=head2 form_value ARGUMENT

Returns a L<Jifty::Web::Form::Field> object that renders a display
value instead of an editable widget for this argument.  If there is no
entry in the L</arguments> hash that matches the given C<ARGUMENT>,
returns C<undef>.

=cut

sub form_value {
    my $self = shift;
    my $arg_name = shift;
    $self->_form_widget( argument => $arg_name,
                         render_mode => 'read',
                         @_);

}

# Generalized helper for the two above
sub _form_widget {
    my $self       = shift;
    my %args = ( argument => undef,
                 render_mode => 'update',
                 @_);

    my $field = $args{'argument'};
    
    my $arg_name = $field. '!!' .$args{'render_mode'};

    if ( not exists $self->{_private_form_fields_hash}{$arg_name} ) {

        my $field_info = $self->arguments->{$field};

        my $sticky = 0;
        # Check stickiness iff the values came from the request
        if(Jifty->web->response->result($self->moniker)) {
            $sticky = 1 if $self->sticky_on_failure and $self->result->failure;
            $sticky = 1 if $self->sticky_on_success and $self->result->success;
        }

        # $sticky can be overrided per-parameter
        $sticky = $field_info->{sticky} if defined $field_info->{sticky};

        if ($field_info) {
            # form_fields overrides stickiness of what the user last entered.
            my $default_value;
            $default_value = $field_info->{'default_value'}
              if exists $field_info->{'default_value'};
            $default_value = $self->argument_value($field)
              if $self->has_argument($field) && !$self->values_from_request->{$field};

            $self->{_private_form_fields_hash}{$arg_name}
                = Jifty::Web::Form::Field->new(
                %$field_info,
                action        => $self,
                name          => $field,
                sticky        => $sticky,
                sticky_value  => $self->argument_value($field),
                default_value => $default_value,
                render_mode   => $args{'render_mode'},
                %args
                );

        }    # else $field remains undef
        else {
            Jifty->log->warn("$arg_name isn't a valid field for $self");
        }
    } elsif ( $args{render_as} ) {
        bless $self->{_private_form_fields_hash}{$arg_name},
          "Jifty::Web::Form::Field::$args{render_as}";
    }
    return $self->{_private_form_fields_hash}{$arg_name};
}

=head2 hidden ARGUMENT VALUE

A shortcut for specifying a form field C<ARGUMENT> which should render
as a hidden form field, with the default value C<VALUE>.

=cut

sub hidden {
    my $self = shift;
    my ($arg, $value, @other) = @_;
    $self->form_field( $arg, render_as => 'hidden', default_value => $value, @other);
}

=head2 order [INTEGER]

Gets or sets the order that the action will be run in.  This should be
an integer, with lower numbers being run first.  Defaults to zero.

=head2 result [RESULT]

Returns the L<Jifty::Result> method associated with this action.  If
an action with the same moniker existed in the B<last> request, then
this contains the results of that action.

=head2 register

Registers this action as being present, by outputting a snippet of
HTML.  This expects that an HTML form has already been opened.  Note
that this is not a guarantee that the action will be run, even if the
form is submitted.  See L<Jifty::Request> for the definition of
"L<active|Jifty::Manual::Glossary/active>" actions.

Normally, L<Jifty::Web/new_action> takes care of calling this when it
is needed.

=cut

sub register {
    my $self = shift;
    Jifty->web->out( qq!<div class="hidden"><input type="hidden"! .
                       qq! name="@{[$self->register_name]}"! .
                       qq! id="@{[$self->register_name]}"! .
                       qq! value="@{[ref($self)]}"! .
                       qq! /></div>\n! );



    my %args = %{$self->arguments};

    while ( my ( $name, $info ) = each %args ) {
        next unless $info->{'constructor'};
        Jifty::Web::Form::Field->new(
            %$info,
            action        => $self,
            input_name    => $self->fallback_form_field_name($name),
            sticky        => 0,
            default_value => ($self->argument_value($name) || $info->{'default_value'}),
            render_as     => 'Hidden'
        )->render();
    }
    return '';
}

=head2 render_errors

Render any the L<Jifty::Result/error> of this action, if any, as HTML.
Returns nothing.

=cut

sub render_errors {
    my $self = shift;
    
    if (defined $self->result->error) {
        # XXX TODO FIXME escape?
        Jifty->web->out( '<div class="form_errors">'
                . '<span class="error">'
                . $self->result->error
                . '</span>'
                . '</div>' );
    }
    return '';
}

=head2 button arguments => { KEY => VALUE }, PARAMHASH

Create and render a button.  It functions nearly identically like
L<Jifty::Web/link>, except it takes C<arguments> in addition to
C<parameters>, and defaults to submitting this L<Jifty::Action>.
Returns nothing. 

Recommended reading: L<Jifty::Web::Form::Element>, where most of 
the cool options to button and other things of its ilk are documented.

=cut

sub button {
    my $self = shift;
    my %args = ( arguments => {},
                 submit    => $self,
                 register  => 0,
                 @_);

    if ($args{register}) {
        # If they ask us to register the action, do so
        Jifty->web->form->register_action( $self );
        Jifty->web->form->print_action_registration($self->moniker);
    } elsif ( not Jifty->web->form->printed_actions->{ $self->moniker } ) {
        # Otherwise, if we're not registered yet, do it in the button
        my $arguments = $self->arguments;
        $args{parameters}{ $self->register_name } = ref $self;
        $args{parameters}{ $self->fallback_form_field_name($_) }
            = $self->argument_value($_) || $arguments->{$_}->{'default_value'}
            for grep { $arguments->{$_}{constructor} } keys %{ $arguments };
    }
    $args{parameters}{$self->form_field_name($_)} = $args{arguments}{$_}
      for keys %{$args{arguments}};

    Jifty->web->link(%args);
}

=head3 return PARAMHASH

Creates and renders a button, like L</button>, which additionally
defaults to calling the current continuation.

Takes an additional argument, C<to>, which can specify a default path
to return to if there is no current continuation.

=cut

sub return {
    my $self = shift;
    my %args = (@_);
    my $continuation = Jifty->web->request->continuation;
    if (not $continuation and $args{to}) {
        $continuation = Jifty::Continuation->new(request => Jifty::Request->new(path => $args{to}));
    }
    delete $args{to};

    $self->button( call => $continuation, %args );
}


=head1 NAMING METHODS

These methods return the names of HTML form elements related to this
action.

=head2 register_name

Returns the name of the "registration" query argument for this action
in a web form.

=cut

sub register_name {
    my $self = shift;
    return 'J:A-' . (defined $self->order ? $self->order . "-" : "") .$self->moniker;
}


sub _prefix_field {
    my $self = shift;
    my ($field_name, $prefix) = @_;
    return join("-", $prefix, $field_name, $self->moniker);
}

=head2 form_field_name ARGUMENT

Turn one of this action's L<arguments|Jifty::Manual::Glossary/arguments> into
a fully qualified name; takes the name of the field as an argument.

=cut

sub form_field_name {
    my $self = shift;
    return $self->_prefix_field(shift, "J:A:F");
}

=head2 fallback_form_field_name ARGUMENT

Turn one of this action's L<arguments|Jifty::Manual::Glossary/arguments> into
a fully qualified "fallback" name; takes the name of the field as an
argument.

This is specifically to support checkboxes, which only show up in the
query string if they are checked.  Jifty creates a checkbox with the
value of L<form_field_name> as its name and a value of 1, and a hidden
input with the value of L<fallback_form_field_name> as its name and a
value of 0; using this information, L<Jifty::Request> can both
determine if the checkbox was present at all in the form, as well as
its true value.

=cut

sub fallback_form_field_name {
    my $self = shift;
    return $self->_prefix_field(shift, "J:A:F:F");
}

=head2 error_div_id ARGUMENT

Turn one of this action's L<arguments|Jifty::Manual::Glossary/arguments> into
the id for the div in which its errors live; takes name of the field
as an argument.

=cut

sub error_div_id {
  my $self = shift;
  my $field_name = shift;
  return 'errors-' . $self->form_field_name($field_name);
}

=head2 warning_div_id ARGUMENT

Turn one of this action's L<arguments|Jifty::Manual::Glossary/arguments> into
the id for the div in which its warnings live; takes name of the field
as an argument.

=cut

sub warning_div_id {
  my $self = shift;
  my $field_name = shift;
  return 'warnings-' . $self->form_field_name($field_name);
}

=head2 canonicalization_note_div_id ARGUMENT

Turn one of this action's L<arguments|Jifty::Manual::Glossary/arguments> into
the id for the div in which its canonicalization notes live; takes name of the field
as an argument.

=cut

sub canonicalization_note_div_id {
  my $self = shift;
  my $field_name = shift;
  return 'canonicalization_note-' . $self->form_field_name($field_name);
}


=head1 VALIDATION METHODS

=head2 argument_names

Returns the list of argument names.  This information is extracted
from L</arguments>.

=cut


sub argument_names {
    my $self      = shift;
    my %arguments = %{ $self->arguments };
    return (
        sort {
            (($arguments{$a}->{'sort_order'} ||0 ) <=> ($arguments{$b}->{'sort_order'} || 0))
                || (($arguments{$a}->{'name'} || '') cmp ($arguments{$b}->{'name'} ||'' ))
                || $a cmp $b
            } keys %arguments
    );
}


=head2 _canonicalize_arguments

Canonicalizes each of the L<arguments|Jifty::Manual::Glossary/arguments> that
this action knows about.

This is done by calling L</_canonicalize_argument> for each field
described by L</arguments>.

=cut

# XXX TODO: This is named with an underscore to prevent infinite
# looping with arguments named "argument" or "arguments".  We need a
# better solution.
sub _canonicalize_arguments {
    my $self   = shift;

    $self->_canonicalize_argument($_)
      for $self->argument_names;
}


=head2 _canonicalize_argument ARGUMENT

Canonicalizes the value of an L<argument|Jifty::Manual::Glossary/argument>.
If the argument has an attribute named B<canonicalizer>, call the
subroutine reference that attribute points points to.

If it doesn't have a B<canonicalizer> attribute, but the action has a
C<canonicalize_I<ARGUMENT>> function, also invoke that function.

If neither of those are true, by default canonicalize dates using
_canonicalize_date

Note that it is possible that a canonicalizer will be called multiple
times on the same field -- canonicalizera should be careful to do
nothing to already-canonicalized data.

=cut

# XXX TODO: This is named with an underscore to prevent infinite
# looping with arguments named "argument" or "arguments".  We need a
# better solution.
sub _canonicalize_argument {
    my $self  = shift;
    my $field = shift;

    my $field_info = $self->arguments->{$field};
    my $value = $self->argument_value($field);
    my $default_method = 'canonicalize_' . $field;

    # XXX TODO: Do we really want to skip undef values?
    return unless defined $value;

    if ( $field_info->{canonicalizer}
        and defined &{ $field_info->{canonicalizer} } )
    {
        $value = $field_info->{canonicalizer}->( $self, $value );
    } elsif ( $self->can($default_method) ) {
        $value = $self->$default_method( $value );
    } elsif (   defined( $field_info->{render_as} )
             && lc( $field_info->{render_as} ) eq 'date') {
        $value = $self->_canonicalize_date( $value );
    }

    $self->argument_value($field => $value);
}


=head2 _canonicalize_date DATE

Parses and returns the date using L<Jifty::DateTime::new_from_string>.

=cut

sub _canonicalize_date {
    my $self = shift;
    my $val = shift;
    return undef unless defined $val and $val =~ /\S/;
    return undef unless my $obj = Jifty::DateTime->new_from_string($val);
    return $obj->ymd;
}

=head2 _validate_arguments

Validates the form fields.  This is done by calling
L</_validate_argument> for each field described by L</arguments>

=cut

# XXX TODO: This is named with an underscore to prevent infinite
# looping with arguments named "argument" or "arguments".  We need a
# better solution.
sub _validate_arguments {
    my $self   = shift;
    
    $self->_validate_argument($_)
      for $self->argument_names;


    return $self->result->success;
}

=head2 _validate_argument ARGUMENT

Validate your form fields.  If the field C<ARGUMENT> is mandatory,
checks for a value.  If the field has an attribute named B<validator>,
call the subroutine reference validator points to.

If the action doesn't have an explicit B<validator> attribute, but
does have a C<validate_I<ARGUMENT>> function, invoke that function.

=cut

# XXX TODO: This is named with an underscore to prevent infinite
# looping with arguments named "argument" or "arguments".  We need a
# better solution.
sub _validate_argument {
    my $self  = shift;
    my $field = shift;

    return unless $field;
    
    $self->log->debug(" validating argument $field");

    my $field_info = $self->arguments->{$field};
    return unless $field_info;

    my $value = $self->argument_value($field);

    if (    $field_info->{mandatory}
        and $self->_is_argument_value_deleted($field) )
    {
        return $self->validation_error( $field => _("You need to fill in this field") );
    }

    # If we have a set of allowed values, let's check that out.
    # XXX TODO this should be a validate_valid_values sub
    if ( $value && $field_info->{valid_values} ) {

        unless ( grep $_->{'value'} eq $value,
            @{ $self->valid_values($field) } )
        {

            return $self->validation_error(
                $field => _("That doesn't look like a correct value") );
        }

   # ... but still check through a validator function even if it's in the list
    }

    my $default_validator = 'validate_' . $field;

    # Finally, fall back to running a validator sub
    if ( $field_info->{validator}
        and defined &{ $field_info->{validator} } )
    {
        return $field_info->{validator}->( $self, $value );
    }

    elsif ( $self->can($default_validator) ) {
        return $self->$default_validator( $value );
    }

    # If none of the checks have failed so far, then it's ok
    else {
        return $self->validation_ok($field);
    }
}

sub _is_argument_value_deleted {
    my $self  = shift;
    my $field = shift;

    my $value = $self->argument_value($field);

    my $field_info = $self->arguments->{$field};
    return unless $field_info;

    my $default_value;
    $default_value = $field_info->{'default_value'}
      if exists $field_info->{'default_value'};
    $default_value = $value
      if $self->has_argument($field) && $value && !$self->values_from_request->{$field};

    if ( not defined $value or not length $value ) {
        if (   ( defined $default_value && $value ne $default_value )
            || ( Jifty->web->request->path !~ m{^/__jifty/validator\.xml} ) )
        {
            return 1;
        }
    }
    return 0;
}

=head2 _autocomplete_argument ARGUMENT

Get back a list of possible completions for C<ARGUMENT>.  The list
should either be a list of scalar values or a list of hash references.
Each hash reference must have a key named C<value>.  There can also
additionally be a key named C<label> which, if present, will be used
as the user visible label.  If C<label> is not present then the
contents of C<value> will be used for the label.

If the field has an attribute named B<autocompleter>, call the
subroutine reference B<autocompleter> points to.

If the field doesn't have an explicit B<autocompleter> attribute, but
does have a C<autocomplete_I<ARGUMENT>> function, invoke that
function.


=cut

# XXX TODO: This is named with an underscore to prevent infinite
# looping with arguments named "argument" or "arguments".  We need a
# better solution.
sub _autocomplete_argument {
    my $self  = shift;
    my $field = shift;
    my $field_info = $self->arguments->{$field};
    my $value = $self->argument_value($field);

    my $default_autocomplete = 'autocomplete_' . $field;

    if ( $field_info->{autocompleter}  )
    {
        return $field_info->{autocompleter}->( $self, $value );
    }

    elsif ( $self->can($default_autocomplete) ) {
        return $self->$default_autocomplete( $value );
    }

}

=head2 valid_values ARGUMENT

Given an L<parameter|Jifty::Manual::Glossary/parameter> name, returns the
list of valid values for it, based on its C<valid_values> field.

This method returns a hash referenece with a C<display> field for the string
to display for the value, and a C<value> field for the value to actually send
to the server.

(Avoid using this -- this is not the appropriate place for this logic
to be!)

=cut

sub valid_values {
    my $self = shift;
    my $field = shift;

    $self->_values_for_field( $field => 'valid' );
}

=head2 available_values ARGUMENT

Just like L<valid_values>, but if our action has a set of available
recommended values, returns that instead. (We use this to
differentiate between a list of acceptable values and a list of
suggested values)

=cut

sub available_values {
    my $self = shift;
    my $field = shift;

    $self->_values_for_field( $field => 'available' ) || $self->_values_for_field( $field => 'valid' );

}

# TODO XXX FIXME this is probably in the wrong place, logically
sub _values_for_field {
    my $self  = shift;
    my $field = shift;
    my $type = shift;

    my $vv_orig = $self->arguments->{$field}{$type .'_values'};
    local $@;
    my @values = eval { @$vv_orig } or return $vv_orig;

    my $vv = [];

    for my $v (@values) {
        if ( ref $v eq 'HASH' ) {
            if ( $v->{'collection'} ) {
                my $disp = $v->{'display_from'};
                my $val  = $v->{'value_from'};
                # XXX TODO: wrap this in an eval?
                push @$vv, map {
                    {
                        display => ( $_->$disp() || '' ),
                        value   => ( $_->$val()  || '' )
                    }
                } grep {$_->check_read_rights} @{ $v->{'collection'}->items_array_ref };

            }
            else {

                # assume it's already display/value
                push @$vv, $v;
            }
        }
        else {

            # just a string
            push @$vv, { display => $v, value => $v };
        }
    }

    return $vv;
}

=head2 validation_error ARGUMENT => ERROR TEXT

Used to report an error during validation.  Inside a validator you
should write:

  return $self->validation_error( $field => "error");

..where C<$field> is the name of the argument which is at fault.

=cut

sub validation_error {
    my $self = shift;
    my $field = shift;
    my $error = shift;
  
    $self->result->field_error($field => $error); 
  
    return 0;
}

=head2 validation_warning ARGUMENT => WARNING TEXT

Used to report a warning during validation.  Inside a validator you
should write:

  return $self->validation_warning( $field => "warning");

..where C<$field> is the name of the argument which is at fault.

=cut

sub validation_warning {
    my $self = shift;
    my $field = shift;
    my $warning = shift;
  
    $self->result->field_warning($field => $warning); 
  
    return 0;
}

=head2 validation_ok ARGUMENT

Used to report that a field B<does> validate.  Inside a validator you
should write:

  return $self->validation_ok($field);

=cut

sub validation_ok {
    my $self = shift;
    my $field = shift;

    $self->result->field_error($field => undef);
    $self->result->field_warning($field => undef);

    return 1;
}

=head2 canonicalization_note ARGUMENT => NOTE

Used to send an informational message to the user from the canonicalizer.  
Inside a canonicalizer you can write:

  $self->canonicalization_note( $field => "I changed $field for you");

..where C<$field> is the name of the argument which the canonicalizer is 
processing

=cut

sub canonicalization_note {
    my $self = shift;
    my $field = shift;
    my $info = shift;
  
    $self->result->field_canonicalization_note($field => $info); 

    return;

}

=head2 autogenerated

Autogenerated Actions will always return true when this method is called. 
"Regular" actions will return false.

=cut

sub autogenerated {0}

1;
