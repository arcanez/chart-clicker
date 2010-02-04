#!/usr/bin/perl
use strict;

use Chart::Clicker;
use Chart::Clicker::Context;
use Chart::Clicker::Data::DataSet;
use Chart::Clicker::Data::Marker;
use Chart::Clicker::Data::Series::Size;
use Chart::Clicker::Renderer::HeatMap;
use Geometry::Primitive::Rectangle;
use Graphics::Color::RGB;

my $cc = Chart::Clicker->new(width => 500, height => 250);

my @hours = qw(
    1 2 3 4 5 6 7 8 9 10 11 12
);
my @bw1 = qw(
    5.8 5.0 4.9 4.8 4.5 4.25 3.5 2.9 2.5 1.8 .9 .8
);

my $series1 = Chart::Clicker::Data::Series::Size->new(
    keys    => \@hours,
    values  => \@bw1,
    sizes    => [qw(1 2 3 4 5 6 7 8 7 6 5 2)]
);

my $ds = Chart::Clicker::Data::DataSet->new(series => [ $series1 ]);

$cc->add_to_datasets($ds);

my $def = $cc->get_context('default');

my $ren = Chart::Clicker::Renderer::HeatMap->new;
$def->renderer($ren);
$def->range_axis->tick_values([qw(1 3 5)]);
$def->range_axis->format('%d');
$def->domain_axis->tick_values([qw(2 4 6 8 10)]);
$def->domain_axis->format('%d');

$cc->write_output('foo.png');
