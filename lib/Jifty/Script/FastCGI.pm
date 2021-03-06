use strict;
use warnings;


package Jifty::Script::FastCGI;
use base qw/Jifty::Script/;

use File::Basename;
use CGI::Fast;

=head1 NAME

Jifty::Script::FastCGI - A FastCGI server for your Jifty application

=head1 SYNOPSIS

    AddHandler fastcgi-script fcgi
    FastCgiServer /path/to/your/jifty/app/bin/jifty -initial-env JIFTY_COMMAND=fastcgi 

  Options:
    --maxrequests      maximum number of requests per process

    --help             brief help message
    --man              full documentation

=head1 DESCRIPTION

FastCGI entry point for your Jifty application

=head2 options

=over 8

=item B<--maxrequests>

Set maximum number of requests per process. Read also --man.

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=cut

sub options {
    my $self = shift;
    return (
        $self->SUPER::options,
        'maxrequests=i' => 'maxrequests',
    );
}

=head1 DESCRIPTION

When you're ready to move up to something that can handle the increasing load your
new world-changing application is generating, you'll need something a bit heavier-duty
than the pure-perl Jifty standalone server.  C<FastCGI> is what you're looking for.

 # These two lines are FastCGI-specific; skip them to run in vanilla CGI mode
 AddHandler fastcgi-script fcgi
 FastCgiServer /path/to/your/jifty/app/bin/jifty -initial-env JIFTY_COMMAND=fastcgi 

 DocumentRoot /path/to/your/jifty/app/share/web/templates
 ScriptAlias / /path/to/your/jifty/app/bin/jifty/

For B<lighttpd> (L<http://www.lighttpd.net/>), use this setting:

 server.modules  = ( "mod_fastcgi" )
 server.document-root = "/path/to/your/jifty/app/share/web/templates"
 fastcgi.server = (
        "" => (
            "your_jifty_app" => (
                "socket"       => "/tmp/your_jifty_app.socket",
                "check-local"  => "disable",
                "bin-path"     => "/path/to/your/jifty/app/bin/jifty",
                "bin-environment" => ( "JIFTY_COMMAND" => "fastcgi" ),
                "min-procs"    => 1,
                "max-procs"    => 5,
                "max-load-per-proc" => 1,
                "idle-timeout" => 20,
            )
        )
    )

If you have MaxRequests options under FastCGI in your config.yml, or
commandline option C<--maxrequests=N> assigned, the fastcgi process
will exit after serving N requests. 

An alternative to Apache mod_fastcgi is to use mod_fcgid with mod_rewrite.
If you use mod_fcgid and mod_rewrite, you can use this in your Apache
configuration instead:

 DocumentRoot /path/to/your/jifty/app/share/web/templates
 ScriptAlias /cgi-bin /path/to/your/jifty/app/bin
 DefaultInitEnv JIFTY_COMMAND fastcgi
 <Directory /path/to/your/jifty/app/bin>
     Options ExecCGI
     SetHandler fcgid-script
 </Directory>
 <Directory /path/to/your/jifty/app/share/web/templates>
     RewriteEngine on
     RewriteRule ^$ index.html [QSA]
     RewriteRule ^(.*)$ /cgi-bin/jifty/$1 [QSA,L]
 </Directory>

It may be possible to do this without using mod_rewrite.

=head1 METHODS

=head2 run

Creates a new FastCGI process.

=cut

sub run {
    my $self = shift;

    $self->print_help;

    Jifty->new();
    my $conf = Jifty->config->framework('Web')->{'FastCGI'} || {};
    $self->{maxrequests} ||= $conf->{MaxRequests};

    my $PATH = $ENV{'PATH'} || '/bin:/usr/bin';

    my $requests = 0;
    while ( my $cgi = CGI::Fast->new ) {
        # the whole point of fastcgi requires the env to get reset here..
        # So we must squash it again
        $ENV{'PATH'}   = $PATH;
        $ENV{'SHELL'}  = '/bin/sh' if defined $ENV{'SHELL'};
        $ENV{'PATH_INFO'}   = $ENV{'SCRIPT_NAME'}
            if $ENV{'SERVER_SOFTWARE'} =~ /^lighttpd\b/;
        for (qw(CDPATH ENV IFS)) {
            $ENV{$_} = '' if (defined $ENV{$_} );
        }
        Jifty->handler->handle_request( cgi => $cgi );
        if ($self->{maxrequests} && ++$requests >= $self->{maxrequests}) {
            exit 0;
        }
    }
}

1;
