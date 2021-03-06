#########
# Author:        gq1
# Created:       2009-05-21
#

use strict;
use warnings;
use Test::More tests => 3;
use English qw(-no_match_vars);
use IO::Scalar;
use t::util;
use npg_qc::model::run_recipe;
;

use_ok('npg_qc::model::run_recipe');


my $util = t::util->new({fixtures =>1});


{
  my $model = npg_qc::model::run_recipe->new({util => $util});
  isa_ok($model, 'npg_qc::model::run_recipe', '$model');
}


{
  my $model = npg_qc::model::run_recipe->new({
     util => $util,
     id_recipe_file => 1,
     });
  is($model->recipe_xml(), q{<?xml version="1.0" ?> <RecipeFile></RecipeFile>}, 'correct recipe xml');
  
}

