package Chart::Clicker::Axis;
use Moose;

extends 'Chart::Clicker::Drawing::Component';

use MooseX::AttributeHelpers;

use constant PI => 4 * atan2 1, 1;

use Chart::Clicker::Context;
use Chart::Clicker::Data::Range;
use Chart::Clicker::Drawing qw(:positions);

use Graphics::Color::RGB;

use Graphics::Primitive::Font;
use Graphics::Primitive::Stroke;

has 'font' => (
    is => 'rw',
    isa => 'Graphics::Primitive::Font',
    default => sub { Graphics::Primitive::Font->new(); }
);
has 'format' => ( is => 'rw', isa => 'Str' );
has 'fudge_amount' => ( is => 'rw', isa => 'Num', default => 0 );
has 'label' => ( is => 'rw', isa => 'Str' );
has 'per' => ( is => 'rw', isa => 'Num' );
# TODO FIxme
has 'position' => ( is => 'rw', isa => 'Num' );
has 'show_ticks' => ( is => 'rw', isa => 'Bool', default => 1 );
has 'tick_length' => ( is => 'rw', isa => 'Num', default => 3 );
has 'ticks' => ( is => 'rw', isa => 'Int', default => 5 );
has 'visible' => ( is => 'rw', isa => 'Bool', default => 1 );

has 'stroke' => (
    is => 'rw',
    isa => 'Graphics::Primitive::Stroke',
    default => sub { Graphics::Primitive::Stroke->new(); }
);

has 'tick_stroke' => (
    is => 'rw',
    isa => 'Graphics::Primitive::Stroke',
    default => sub { Graphics::Primitive::Stroke->new(); }
);

has 'tick_values' => (
    metaclass => 'Collection::Array',
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] },
    provides => {
        'push' => 'add_to_tick_values',
        'clear' => 'clear_tick_values',
        'count' => 'tick_value_count'
    }
);
has 'tick_labels' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] }
);

has 'range' => (
    is => 'rw',
    isa => 'Chart::Clicker::Data::Range',
    default => sub { Chart::Clicker::Data::Range->new() }
);

has '+color' => (
    default => sub {
        Graphics::Color::RGB->new({
            red => 0, green => 0, blue => 0, alpha => 1
        })
    },
    coerce => 1
);

has 'baseline' => (
    is  => 'rw',
    isa => 'Num',
);

sub prepare {
    my $self = shift();

    if($self->range->span() == 0) {
        die('This axis has a span of 0, that\'s fatal!');
    }

    if(defined($self->baseline())) {
        if($self->range->lower() > $self->baseline()) {
            $self->range->lower($self->baseline());
        }
    } else {
        $self->baseline($self->range->lower());
    }

    if($self->fudge_amount()) {
        my $span = $self->range->span();
        my $lower = $self->range->lower();
        $self->range->lower($lower - abs($span * $self->fudge_amount()));
        my $upper = $self->range->upper();
        $self->range->upper($upper + ($span * $self->fudge_amount()));
    }

    if(!scalar(@{ $self->tick_values() })) {
        $self->tick_values($self->range->divvy($self->ticks()));
    }

    my $cairo = $self->clicker->cairo();

    my $font = $self->font();

    $cairo->set_font_size($font->size());
    $cairo->select_font_face(
        $font->face(), $font->slant(), $font->weight()
    );

    # Determine all this once... much faster.
    my $biggest = 0;
    my $key;
    if($self->visible()) {
        if($self->orientation() == $CC_HORIZONTAL) {
            $key = 'total_height';
        } else {
            $key = 'width';
        }
        my @values = @{ $self->tick_values() };
        for(0..scalar(@values) - 1) {
            my $val = $self->format_value($self->tick_labels->[$_] || $values[$_]);
            my $ext = $cairo->text_extents($val);
            $ext->{total_height} = $ext->{height} - $ext->{y_bearing};
            $self->{'ticks_extents_cache'}->[$_] = $ext;
            if($ext->{$key} > $biggest) {
                $biggest = $ext->{$key};
            }
        }

        if($self->show_ticks()) {
            $biggest += $self->tick_length();
        }
    }

    if ($self->label()) {
        my $ext = $cairo->text_extents($self->label());
        $ext->{total_height} = $ext->{height} - $ext->{y_bearing};
        $self->{'label_extents_cache'} = $ext;
    }

    if($self->orientation() == $CC_HORIZONTAL) {
        my $label_height = $self->label()
            ? $self->{'label_extents_cache'}->{'total_height'}
            : 0;
        $self->minimum_height($biggest + $label_height + 4);
        # TODO Wrong, need widest label + tick length + outside
        $self->minimum_width($biggest + $self->outside_width);
        # TODO This is wrong
        # $self->per($self->width / ($self->range->span - 1));
    } else {
        # The label will be rotated, so use height here too.
        my $label_width = $self->label()
            ? $self->{'label_extents_cache'}->{'total_height'}
            : 0;
        $self->minimum_width($biggest + $label_width + 4);
        # TODO Wrong, need tallest label + tick length + outside
        $self->minimum_height($self->outside_height + $biggest);
        # TODO This is wrong
        # $self->per($self->height() / ($self->range->span() - 1));
    }

    return 1;
}

sub mark {
    my $self = shift();
    my $value = shift();

    # 'caching' this here speeds things up.  Calling after changing the
    # range would result in a messed up chart anyway...
    if(!defined($self->{'LOWER'})) {
        $self->{'LOWER'} = $self->range->lower();
    }
    return $self->per() * ($value - $self->{'LOWER'} || 0);
}

sub draw {
    my $self = shift();

    if($self->orientation() == $CC_HORIZONTAL) {
        $self->per($self->width / ($self->range->span - 1));
    } else {
        $self->per($self->height() / ($self->range->span() - 1));
    }

    unless($self->visible()) {
        return;
    }

    my $x = 0;
    my $y = 0;

    my $orient = $self->orientation();
    my $pos = $self->position();
    my $width = $self->width();
    my $height = $self->height();


    if($pos == $CC_LEFT) {
        $x += $width;
    } elsif($pos == $CC_RIGHT) {
        # nuffin
    } elsif($pos == $CC_TOP) {
        $y += $height;
    } else {
        # nuffin
    }

    my $cr = $self->clicker->cairo();

    my $stroke = $self->stroke();
    $cr->set_line_width($stroke->width());
    $cr->set_line_cap($stroke->line_cap());
    $cr->set_line_join($stroke->line_join());

    my $font = $self->font();
    $cr->set_font_size($font->size());
    $cr->select_font_face(
        $font->face(), $font->slant(), $font->weight()
    );

    my $tick_length = $self->tick_length();
    my $per = $self->per();

    my $lower = $self->range->lower();

    $cr->set_source_rgba($self->color->as_array_with_alpha());

    $cr->move_to($x, $y);
    if($orient == $CC_HORIZONTAL) {
        # Draw a line for our axis
        $cr->line_to($x + $width, $y);

        my @values = @{ $self->tick_values() };
        # Draw a tick for each value.
        for(0..scalar(@values) - 1) {
            my $val = $values[$_];
            # Grab the extent from the cache.
            my $ext = $self->{'ticks_extents_cache'}->[$_];
            my $ix = $x + ($val - $lower) * $per;
            $cr->move_to($ix, $y);
            if($pos == $CC_TOP) {
                $cr->line_to($ix, $y - $tick_length);
                $cr->rel_move_to(-($ext->{'width'} / 1.8), -2);
            } else {
                $cr->line_to($ix, $y + $tick_length);
                $cr->rel_move_to(-($ext->{'width'} / 2), $ext->{'height'} + 2);
            }
            $cr->show_text($self->format_value($self->tick_labels->[$_] || $val));
        }

        # Draw the label
        if($self->label()) {
            my $ext = $self->{'label_extents_cache'};
            if ($pos == $CC_BOTTOM) {
                $cr->move_to(($width - $ext->{'width'}) / 2, $height);
            } else {
                $cr->move_to(($width - $ext->{'width'}) / 2, $ext->{'height'} + 2);
            }
            $cr->show_text($self->label());
        }

    } else {
        $cr->line_to($x, $y + $height);

        my @values = @{ $self->tick_values() };
        for(0..scalar(@values) - 1) {
            my $val = $values[$_];
            my $iy = $y + $height - (($val - $lower) * $per);
            my $ext = $self->{'ticks_extents_cache'}->[$_];
            $cr->move_to($x, $iy);
            if($self->position() == $CC_LEFT) {
                $cr->line_to($x - $tick_length, $iy);
                $cr->rel_move_to(-$ext->{'width'} - 2, $ext->{'height'} / 2);
            } else {
                $cr->line_to($x + $tick_length, $iy);
                $cr->rel_move_to(0, $ext->{'height'} / 2);
            }
            $cr->show_text($self->format_value($val));
        }

        # Draw the label
        if($self->label()) {
            my $ext = $self->{'label_extents_cache'};
            if ($pos == $CC_LEFT) {
                $cr->move_to($ext->{'height'}, ($height + $ext->{'width'}) / 2);
                $cr->rotate(3*PI/2);
            } else {
                $cr->move_to($width - $ext->{'height'}, ($height - $ext->{'width'}) / 2);
                $cr->rotate(PI/2);
            }
            $cr->show_text($self->label());
        }
    }

    $cr->stroke();
}

sub format_value {
    my $self = shift;
    my $value = shift;

    if($self->format()) {
        return sprintf($self->format(), $value);
    }
    return $value;
}

1;
__END__

=head1 NAME

Chart::Clicker::Axis

=head1 DESCRIPTION

Chart::Clicker::Axis represents the plot of the chart.

=head1 SYNOPSIS

  use Chart::Clicker::Axis;
  use Chart::Clicker::Drawing qw(:positions);
  use Chart::Clicker::Drawing::Color;
  use Chart::Clicker::Drawing::Font;
  use Chart::Clicker::Drawing::Stroke;

  my $axis = Chart::Clicker::Axis->new({
    color => 'black',
    font  => Chart::Clicker::Drawing::Font->new(),
    orientation => $CC_VERTICAL,
    position => $CC_LEFT,
    show_ticks => 1,
    stroke = Chart::Clicker::Drawing::Stroke->new(),
    tick_length => 2,
    tick_stroke => Chart::Clicker::Drawing::Stroke->new(),
    visible => 1,
  });

=head1 METHODS

=head2 Constructor

=over 4

=item Chart::Clicker::Axis->new()

Creates a new Chart::Clicker::Axis.  If no arguments are given then sane
defaults are chosen.

=back

=head2 Class Methods

=over 4

=item baseline

Set the 'baseline' value of this axis.  This is used by some renderers to
change the way a value is marked.  The Bar render, for instance, considers
values below the base to be 'negative'.

=item color

Set/Get the color of the axis.

=item font

Set/Get the font used for the axis' labels.

=item format

Set/Get the format to use for the axis values.  The format is applied to each
value 'tick' via sprintf().  See sprintf()s perldoc for details!  This is
useful for situations where the values end up with repeating decimals.

=item fudge_amount

Set/Get the amount to 'fudge' the span of this axis.  You should supply a
percentage (in decimal form) and the axis will grow at both ends by the
supplied amount.  This is useful when you want a bit of padding above and
below the dataset.

As an example, a fugdge_amount of .10 on an axis with a span of 10 to 50
would add 5 to the top and bottom of the axis.

=item height

Set/Get the height of the axis.

=item label

Set/Get the label of the axis.

=item orientation

Set/Get the orientation of this axis.

=item per

Set/Get the 'per' value for the axis.  This is how many physical pixels a unit
on the axis represents.  If the axis represents a range of 0-100 and the axis
is 200 pixels high then the per value will be 2.

=item position

Set/Get the position of the axis on the chart.

=item range

Set/Get the Range for this axis.

=item show_ticks

Set/Get the show ticks flag.  If this is value then the small tick marks at
each mark on the axis will not be drawn.

=item stroke

Set/Get the stroke for this axis.

=item tick_length

Set/Get the tick length.

=item tick_stroke

Set/Get the stroke for the tick markers.

=item tick_values

Set/Get the arrayref of values show as ticks on this Axis.

=item I<add_to_tick_values>

Add a value to the list of tick values.

=item I<clear_tick_values>

Clear all tick values.

=item I<tick_value_count>

Get a count of tick values.

=item tick_labels

Set/Get the arrayref of labels to show for ticks on this Axis.  This arrayref
is consulted for every tick, in order.  So placing a string at the zeroeth
index will result in it being displayed on the zeroeth tick, etc, etc.

=item ticks

Set/Get the number of 'ticks' to show.  Setting this will divide the
range on this axis by the specified value to establish tick values.  This
will have no effect if you specify tick_values.

=item mark

Given a value, returns it's pixel position on this Axis.

=item format_value

Given a value, returns it formatted using this Axis' formatter.

=item examine_values

Gives the axis an opportunity to examine values.

=item prepare

Prepare this Axis by determining the size required.  If the orientation is
CC_HORIZONTAL this method sets the height.  Otherwise sets the width.

=item draw

Draw this axis.

=item visible

Set/Get this axis visibility flag.

=item width

Set/Get this axis' width.

=back

=head1 AUTHOR

Cory 'G' Watson <gphat@cpan.org>

=head1 SEE ALSO

perl(1)

=head1 LICENSE

You can redistribute and/or modify this code under the same terms as Perl
itself.
