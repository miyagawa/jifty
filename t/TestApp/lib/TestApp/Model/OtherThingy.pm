use strict;
use warnings;

package TestApp::Model::OtherThingy;
use Jifty::DBI::Schema;

use TestApp::Record schema {

  column value => type is 'text',  is mandatory;
  column user_id => refers_to TestApp::Model::User;

};

use Jifty::RightsFrom column => 'user_id';

1;

