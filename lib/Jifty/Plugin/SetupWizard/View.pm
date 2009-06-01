package Jifty::Plugin::SetupWizard::View;
use strict;
use warnings;
use Jifty::View::Declare -base;

template '/__jifty/admin/setupwizard' => page {
    my $appname = Jifty->config->framework('ApplicationName');
    h1 { "Welcome to $appname!" };

    render_region(
        name      => 'WizardStep',
        path      => "/__jifty/admin/setupwizard/step",
        arguments => {
            step => 0,
        },
    );

    p { _("You're seeing this configuration because you started $appname in AdminMode and the SetupWizard plugin. Disable one or both of these to restore normal operation.") };
};

template '/__jifty/admin/setupwizard/step' => sub {
    my $step = get('step');
    my $steps = Jifty->find_plugin('Jifty::Plugin::SetupWizard')->steps;
    my $step_info = $steps->[$step] or abort(400);

    div {
        class is 'setupwizard-step';

        form {
            h3 { $step_info->{header} } if $step_info->{header};

            show "/__jifty/admin/setupwizard/$step_info->{template}";
            form_submit(label => _('Save'));
        };
    };

    div {
        class is 'setupwizard-links';
        step_link(
            index => $step - 1,
            label => "Back: %1",
        );
        br {};
        step_link(
            index => $step + 1,
            label => "Skip to: %1",
        );
    };
};

sub step_link {
    my %args = (
        index => 0,
        label => "%1",
        @_,
    );

    my $index = $args{index};

    my $steps = Jifty->find_plugin('Jifty::Plugin::SetupWizard')->steps;
    return unless $index >= 0 && $index < @$steps;

    my $info = $steps->[$index];
    my $name = $info->{link} || $info->{header} || $info->{template};

    hyperlink(
        label => _($args{label}, $name),
        onclick => {
            replace_self => 1,
            arguments => {
                step => $index,
            },
        },
    );
}

sub config_field {
    my %args = @_;

    my $action = new_action('AddConfig');

    my %value_args = %{ $args{value_args} || {} };

    # Grab a sensible default, the current value of config
    if (!exists($value_args{default_value})) {
        $value_args{default_value} ||= Jifty->config->contextual_get($args{context}, $args{field});
    }

    outs_raw($action->form_field('value' => %value_args));

    for my $field (qw/field context target_file/) {
        outs_raw($action->form_field(
            $field,
            render_as => 'hidden',
            (exists($args{$field}) ? (default_value => $args{$field}) : ()),
        ));
    }
}

template '/__jifty/admin/setupwizard/language' => sub {
    p { _("You may select a different language.") };
};

template '/__jifty/admin/setupwizard/database' => sub {
    p { _("You may choose a database engine.") };
};

template '/__jifty/admin/setupwizard/web' => sub {
    p { _("You may change web server settings.") };
};

template '/__jifty/admin/setupwizard/finalize' => sub {
    p { _("You may finalize your configuration.") };
};

1;
