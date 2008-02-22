#!/usr/bin/env perl
use warnings;
use strict;

use Test::More;
BEGIN {
    if (eval { require Net::OAuth::Request; require Crypt::OpenSSL::RSA; 1 }) {
        plan tests => 22;
    }
    else {
        plan skip_all => "Net::OAuth or Crypt::OpenSSL::RSA isn't installed";
    }
}

use lib 't/lib';
use Jifty::SubTest;

use TestApp::Plugin::OAuth::Test;

use Jifty::Test::WWW::Mechanize;

# setup {{{
# create two consumers {{{
my $consumer = Jifty::Plugin::OAuth::Model::Consumer->new(current_user => Jifty::CurrentUser->superuser);
my ($ok, $msg) = $consumer->create(
    consumer_key => 'foo',
    secret       => 'bar',
    name         => 'FooBar Industries',
    url          => 'http://foo.bar.example.com',
    rsa_key      => $pubkey,
);
ok($ok, $msg);

my $rsaless = Jifty::Plugin::OAuth::Model::Consumer->new(current_user => Jifty::CurrentUser->superuser);
($ok, $msg) = $rsaless->create(
    consumer_key => 'foo2',
    secret       => 'bar2',
    name         => 'Backwater.org',
    url          => 'http://backwater.org',
);
ok($ok, $msg);
# }}}
# create user and log in {{{
my $u = TestApp::Plugin::OAuth::Model::User->new(current_user => TestApp::Plugin::OAuth::CurrentUser->superuser);
$u->create( name => 'You Zer', email => 'youzer@example.com', password => 'secret', email_confirmed => 1);
my $uid = $u->id;
ok($uid, "New user has valid id set");

$umech->get_ok($URL . '/login');
$umech->fill_in_action_ok($umech->moniker_for('TestApp::Plugin::OAuth::Action::Login'), email => 'youzer@example.com', password => 'secret');
$umech->submit;
$umech->content_contains('Logout');
# }}}
# }}}
# make sure we're not logged in {{{
response_is(
    url                    => '/nuke/the/whales',
    code                   => 200,
    testname               => "200 - protected resource request",
    consumer_secret        => 'bar',
    oauth_consumer_key     => 'foo',
    oauth_signature_method => 'PLAINTEXT',
    oauth_token            => 'please',
    token_secret           => 'letmein',
);
$cmech->content_contains("Login with a password", "redirected to login");
$cmech->content_lacks("Press the shiny red button", "did NOT get to a protected page");
# }}}}
# REST GET {{{
get_access_token();

response_is(
    url                    => "/=/model/User/id/$uid.yml",
    code                   => 200,
    method                 => 'GET',
    testname               => "200 - protected resource request",
    consumer_secret        => 'bar',
    oauth_consumer_key     => 'foo',
    oauth_signature_method => 'PLAINTEXT',
    oauth_token            => $token_obj->token,
    token_secret           => $token_obj->secret,
);
$cmech->content_contains("You Zer", "REST GET works while OAuthed");
# }}}
# REST DELETE {{{
response_is(
    url                    => "/=/model/User/id/$uid.yml!DELETE",
    id                     => $uid,
    code                   => 200,
    method                 => 'POST',
    testname               => "200 - protected resource request",
    consumer_secret        => 'bar',
    oauth_consumer_key     => 'foo',
    oauth_signature_method => 'PLAINTEXT',
    oauth_token            => $token_obj->token,
    token_secret           => $token_obj->secret,
);

$cmech->content_like(qr/failure: 1/, "failed to delete");

my $user_copy = TestApp::Plugin::OAuth::Model::User->new(current_user => Jifty::CurrentUser->superuser);
$user_copy->load($uid);
is($user_copy->name, "You Zer", "REST DELETE doesn't work while the consumer has no write access");
# }}}
