package Ora2Pg::PLSQL;
#------------------------------------------------------------------------------
# Project  : Oracle to PostgreSQL database schema converter
# Name     : Ora2Pg/PLSQL.pm
# Language : Perl
# Authors  : Gilles Darold, gilles _AT_ darold _DOT_ net
# Copyright: Copyright (c) 2000-2012 : Gilles Darold - All rights reserved -
# Function : Perl module used to convert Oracle PLSQL code into PL/PGSQL
# Usage    : See documentation
#------------------------------------------------------------------------------
#
#        This program is free software: you can redistribute it and/or modify
#        it under the terms of the GNU General Public License as published by
#        the Free Software Foundation, either version 3 of the License, or
#        any later version.
# 
#        This program is distributed in the hope that it will be useful,
#        but WITHOUT ANY WARRANTY; without even the implied warranty of
#        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#        GNU General Public License for more details.
# 
#        You should have received a copy of the GNU General Public License
#        along with this program. If not, see < http://www.gnu.org/licenses/ >.
# 
#------------------------------------------------------------------------------

use vars qw($VERSION %OBJECT_SCORE $SIZE_SCORE %UNCOVERED_SCORE);
use POSIX qw(locale_h);

#set locale to LC_NUMERIC C
setlocale(LC_NUMERIC,"C");


$VERSION = '9.3';

#----------------------------------------------------
# Cost scores used when converting PLSQL to PLPGSQL
#----------------------------------------------------

# Scores associated to each database objects:
%OBJECT_SCORE = (
	'CLUSTER' => 0, # Not supported and no equivalent
	'FUNCTION' => 1, # read/adapt the header
	'INDEX' => 1, # Read/adapt - use varcharops like operator ?
	'FUNCTION-BASED-INDEX' => 1, # Check code of function call
	'REV-INDEX' => 1, # Check/rewrite the index to use trigram
	'CHECK' => 0.1, # Check/adapt the check constraint
	'MATERIALIZED VIEW' => 3, # Read/adapt, will just concern automatic snapshot export
	'PACKAGE BODY' => 3, # Look at globals variables
	'PROCEDURE' => 1, # read/adapt the header
	'SEQUENCE' => 0.5, # read/adapt to convert name.nextval() into nextval('name')
	'TABLE' => 0.5, # read/adapt the column type/name
	'TABLE PARTITION' => 3, # Read/check that table partitionning is ok
	'TRIGGER' => 1, # read/adapt the header
	'TYPE' => 1, # read
	'TYPE BODY' => 10, # Not directly supported need adaptation
	'VIEW' => 1, # read/adapt
	'DATABASE LINK' => 6, # Not directly supported need adaptation
	'DIMENSION' => 0, # Not supported and no equivalent
	'JOB' => 2, # read/adapt
);

# Scores following the number of lines: number of lines for one unit
# Note: his correspond to the global read time not to the difficulty.
$SIZE_SCORE = 100;

# Scores associated to each code difficulties.
%UNCOVERED_SCORE = (
	'FROM' => 1,
	'TRUNC' => 2,
	'DECODE' => 2,
	'IS TABLE OF' => 4,
	'OUTER JOIN' => 3,
	'CONNECT BY' => 4,
	'BULK COLLECT' => 3,
	'GOTO' => 2,
	'FORALL' => 1,
	'ROWNUM' => 2,
	'NOTFOUND' => 2,
	'ROWID' => 2,
	'IS RECORD' => 1,
	'SQLCODE' => 2,
	'TABLE' => 3,
	'DBMS_' => 3,
	'UTL_' => 3,
	'CTX_' => 3,
	'EXTRACT' => 3,
	'EXCEPTION' => 2,
	'SUBSTR' => 1,
	'TO_NUMBER' => 1,
	'REGEXP_LIKE' => 1,
	'TG_OP' => 1,
	'CURSOR' => 2,
	'PIPE ROW' => 1,
	'ORA_ROWSCN' => 3,
	'SAVEPOINT' => 1,
	'DBLINK' => 4,
	'PLVDATE' => 2,
	'PLVSTR' => 2,
	'PLVCHR' => 2,
	'PLVSUBST' => 2,
	'PLVLEX' => 2,
	'PLUNIT' => 2,
	'ADD_MONTHS' => 1,
	'LAST_DATE' => 1,
	'NEXT_DAY' => 1,
	'MONTHS_BETWEEN' => 1,
	'NVL2' => 1,
);

=head1 NAME

PSQL - Oracle to PostgreSQL procedural language converter


=head1 SYNOPSIS

	This external perl module is used to convert PLSQL code to PLPGSQL.
	It is in an external code to allow easy editing and modification.
	This converter is a work in progress and need your help.

	It is called internally by Ora2Pg.pm when you set PLSQL_PGSQL 
	configuration option to 1.
=cut

=head2 plsql_to_plpgsql

This function return a PLSQL code translated to PLPGSQL code

=cut

sub plsql_to_plpgsql
{
        my ($str, $allow_code_break, $null_equal_empty, $export_type) = @_;

	#--------------------------------------------
	# PL/SQL to PL/PGSQL code conversion
	# Feel free to add your contribution here.
	#--------------------------------------------
	# Change NVL to COALESCE
	$str =~ s/NVL[\s\t]*\(/coalesce(/igs;
	# Change SYSDATE to 'now' or current timestamp.
	$str =~ s/SYSDATE[\s\t]*\([\s\t]*\)/LOCALTIMESTAMP/igs;
	$str =~ s/SYSDATE/LOCALTIMESTAMP/igs;
	# Replace sysdate +/- N by localtimestamp - 1 day intervel
	#$str =~ s/LOCALTIMESTAMP([\s\t]*\-|\+[\s\t]*)(\d+)[\s\t]*,/LOCALTIMESTAMP$1'$2 day'\:\:interval,/igs;
	# remove FROM DUAL
	$str =~ s/FROM DUAL//igs;

	# Converting triggers
	#       :new. -> NEW.
	$str =~ s/([^\w]+):new\./$1NEW\./igs;
	#       :old. -> OLD.
	$str =~ s/([^\w]+):old\./$1OLD\./igs;

	# Replace EXEC function into variable, ex: EXEC :a := test(:r,1,2,3);
	$str =~ s/EXEC[\s\t]+:([^\s\t:]+)[\s\t]*:=/SELECT INTO $2/igs;

	# Replace simple EXEC function call by SELECT function
	$str =~ s/EXEC([\s\t]+)/SELECT$1/igs;

	# Remove leading : on Oracle variable
	$str =~ s/([^\w]+):(\w+)/$1$2/igs;

	# INSERTING|DELETING|UPDATING -> TG_OP = 'INSERT'|'DELETE'|'UPDATE'
	$str =~ s/INSERTING/TG_OP = 'INSERT'/igs;
	$str =~ s/DELETING/TG_OP = 'DELETE'/igs;
	$str =~ s/UPDATING/TG_OP = 'UPDATE'/igs;

	# EXECUTE IMMEDIATE => EXECUTE
	$str =~ s/EXECUTE IMMEDIATE/EXECUTE/igs;

	# SELECT without INTO should be PERFORM. Exclude select of view when prefixed with AS ot IS
	if ($export_type ne 'QUERY') {
		$str =~ s/([\s\t\n\r]+)(?<!AS|IS)([\s\t\n\r]+)SELECT(?![^;]+\bINTO\b[^;]+FROM[^;]+;)/$1$2$3PERFORM$4/isg;
		$str =~ s/\b(AS|IS)([\s\t\n\r]+)PERFORM/$1$2SELECT/isg;
	}

	# Change nextval on sequence
	# Oracle's sequence grammar is sequence_name.nextval.
	# Postgres's sequence grammar is nextval('sequence_name'). 
	$str =~ s/(\w+)\.nextval/nextval('\L$1\E')/isg;
	$str =~ s/(\w+)\.currval/currval('\L$1\E')/isg;
	# Oracle MINUS can be replaced by EXCEPT as is
	$str =~ s/\bMINUS\b/EXCEPT/igs;
	# Raise information to the client
	$str =~ s/DBMS_OUTPUT\.(put_line|put|new_line)*\((.*?)\);/&raise_output($2)/igse;

	# Substitution to replace type of sql variable in PLSQL code
	foreach my $t (keys %Ora2Pg::TYPE) {
		$str =~ s/\b$t\b/$Ora2Pg::TYPE{$t}/igs;
	}
	# Procedure are the same as function in PG
	$str =~ s/\bPROCEDURE\b/FUNCTION/igs;
	# Simply remove this as not supported
	$str =~ s/\bDEFAULT NULL\b//igs;

	# dup_val_on_index => unique_violation : already exist exception
	$str =~ s/\bdup_val_on_index\b/unique_violation/igs;

	# Replace raise_application_error by PG standard RAISE EXCEPTION
	$str =~ s/\braise_application_error[\s\t]*\([\s\t]*[\-\+]*\d+[\s\t]*,[\s\t]*(.*?)\);/RAISE EXCEPTION $1;/igs;
	# and then rewrite RAISE EXCEPTION concatenations
	while ($str =~ /RAISE EXCEPTION[\s\t]*([^;\|]+?)(\|\|)([^;]*);/) {
		my @ctt = split(/\|\|/, "$1$2$3");
		my $sbt = '';
		my @args = '';
		for (my $i = 0; $i <= $#ctt; $i++) {
			if (($ctt[$i] =~ s/^[\s\t]*'//s) && ($ctt[$i] =~ s/'[\s\t]*$//s)) {
				$sbt .= "$ctt[$i]";
			} else {
				$sbt .= '%';
				push(@args, $ctt[$i]);
			}
		}
		$sbt = "'$sbt'";
		if ($#args >= 0) {
			$sbt = $sbt . join(',', @args);
		}
		$str =~ s/RAISE EXCEPTION[\s\t]*([^;\|]+?)(\|\|)([^;]*);/RAISE EXCEPTION $sbt;/is
	};

	# Remove IN information from cursor declaration
	while ($str =~ s/(\bCURSOR\b[^\(]+)\(([^\)]+\bIN\b[^\)]+)\)/$1\(\%\%CURSORREPLACE\%\%\)/is) {
		my $args = $2;
		$args =~ s/\bIN\b//igs;
		$str =~ s/\%\%CURSORREPLACE\%\%/$args/is;
	}

	# Reorder cursor declaration
	$str =~ s/\bCURSOR\b[\s\t]*([A-Z0-9_\$]+)/$1 CURSOR/isg;

	# Replace CURSOR IS SELECT by CURSOR FOR SELECT
	$str =~ s/\bCURSOR([\s\t]*)IS([\s\t]*)SELECT/CURSOR$1FOR$2SELECT/isg;
	# Replace CURSOR (param) IS SELECT by CURSOR FOR SELECT
	$str =~ s/\bCURSOR([\s\t]*\([^\)]+\)[\s\t]*)IS([\s\t]*)SELECT/CURSOR$1FOR$2SELECT/isg;

	# Rewrite TO_DATE formating call
	$str =~ s/TO_DATE[\s\t]*\([\s\t]*('[^\']+'),[\s\t]*('[^\']+')[^\)]*\)/to_date($1,$2)/igs;

	# Normalize HAVING ... GROUP BY into GROUP BY ... HAVING clause	
	$str =~ s/\bHAVING\b(.*?)\bGROUP BY\b(.*?)((?=UNION|ORDER BY|LIMIT|INTO |FOR UPDATE|PROCEDURE)|$)/GROUP BY$2 HAVING$1/gis;

	# Cast round() call as numeric => Remove because most of the time this may not be necessary
	#$str =~ s/round[\s\t]*\((.*?),([\s\t\d]+)\)/round\($1::numeric,$2\)/igs;

	# Convert the call to the Oracle function add_months() into Pg syntax
	$str =~ s/add_months[\s\t]*\([\s\t]*to_char\([\s\t]*([^,]+)(.*?),[\s\t]*([\-\d]+)[\s\t]*\)/$1 + '$3 month'::interval/gsi;
	$str =~ s/add_months[\s\t]*\((.*?),[\s\t]*([\-\d]+)[\s\t]*\)/$1 + '$2 month'::interval/gsi;

	# Convert the call to the Oracle function add_years() into Pg syntax
	$str =~ s/add_years[\s\t]*\([\s\t]*to_char\([\s\t]*([^,]+)(.*?),[\s\t]*([\-\d]+)[\s\t]*\)/$1 + '$3 year'::interval/gsi;
	$str =~ s/add_years[\s\t]*\((.*?),[\s\t]*([\-\d]+)[\s\t]*\)/$1 + '$2 year'::interval/gsi;

	# Add STRICT keyword when select...into and an exception with NO_DATA_FOUND/TOO_MANY_ROW is present
	if ($str !~ s/(SELECT.*?INTO)(.*?)(EXCEPTION.*?NO_DATA_FOUND)/$1 STRICT $2 $3/igs) {
		$str =~ s/(SELECT.*?INTO)(.*?)(EXCEPTION.*?TOO_MANY_ROW)/$1 STRICT $2 $3/igs;
	}

	# Remove the function name repetion at end
	$str =~ s/END[\s\t]+(?!IF|LOOP|CASE|INTO|FROM|,)[a-z0-9_]+[\s\t]*([;]*)$/END$1/igs;

	# Replace ending ROWNUM with LIMIT
	$str =~ s/(WHERE|AND)[\s\t]*ROWNUM[\s\t]*=[\s\t]*(\d+)/LIMIT 1 OFFSET $2/igs;
	$str =~ s/(WHERE|AND)[\s\t]*ROWNUM[\s\t]*<=[\s\t]*(\d+)/LIMIT $2/igs;
	$str =~ s/(WHERE|AND)[\s\t]*ROWNUM[\s\t]*>=[\s\t]*(\d+)/LIMIT ALL OFFSET $2/igs;
	while ($str =~ /(WHERE|AND)[\s\t]*ROWNUM[\s\t]*<[\s\t]*(\d+)/is) {
		my $limit = $2 - 1;
		$str =~ s/(WHERE|AND)[\s\t]*ROWNUM[\s\t]*<[\s\t]*(\d+)/LIMIT $limit/is;
	}
	while ($str =~ /(WHERE|AND)[\s\t]*ROWNUM[\s\t]*>[\s\t]*(\d+)/is) {
		my $offset = $2 + 1;
		$str =~ s/(WHERE|AND)[\s\t]*ROWNUM[\s\t]*>[\s\t]*(\d+)/LIMIT ALL OFFSET $offset/is;
	}

	# Rewrite comment in CASE between WHEN and THEN
	$str =~ s/([\s\t]*)(WHEN[\s\t]+[^\s\t]+[\s\t]*)(ORA2PG_COMMENT\d+\%)([\s\t]*THEN)/$1$3$1$2$4/igs;

	if ($null_equal_empty) {
		# Rewrite all IF ... IS NULL with coalesce because for Oracle empty and NULL is the same
		$str =~ s/([a-z0-9_\.]+)[\s\t]+IS NULL/coalesce($1::text, '') = ''/igs;
		$str =~ s/([a-z0-9_\.]+)[\s\t]+IS NOT NULL/($1 IS NOT NULL AND $1::text <> '')/igs;
	}

	# Replace SQLCODE by SQLSTATE
	$str =~ s/\bSQLCODE\b/SQLSTATE/igs;

	# Replace some way of extracting date part of a date
	$str =~ s/TO_NUMBER[\s\t]*\([\s\t]*TO_CHAR[\s\t]*\(([^,]+),[\s\t]*('[^']+')[\s\t]*\)[\s\t]*\)/to_char($1, $2)::integer/igs;

	# Replace the UTC convertion with the PG syntaxe
	 $str =~ s/SYS_EXTRACT_UTC[\s\t]*\(([^\)]+)\)/$1 AT TIME ZONE 'UTC'/isg;

	# Revert order in FOR IN REVERSE
	$str =~ s/FOR(.*?)IN[\s\t]+REVERSE[\s\t]+([^\.\s\t]+)[\s\t]*\.\.[\s\t]*([^\s\t]+)/FOR$1IN REVERSE $3..$2/isg;

	# Replace exit at end of cursor
	$str =~ s/EXIT WHEN ([^\%]+)\%NOTFOUND[\s\t]*;/IF NOT FOUND THEN EXIT; END IF; -- apply on $1/isg;
	$str =~ s/EXIT WHEN \([\s\t]*([^\%]+)\%NOTFOUND[\s\t]*\)[\s\t]*;/IF NOT FOUND THEN EXIT; END IF; -- apply on $1/isg;
	# Same but with additional conditions
	$str =~ s/EXIT WHEN ([^\%]+)\%NOTFOUND[\s\t]+([;]+);/IF NOT FOUND $2 THEN EXIT; END IF; -- apply on $1/isg;
	$str =~ s/EXIT WHEN \([\s\t]*([^\%]+)\%NOTFOUND[\s\t]+([\)]+)\)[\s\t]*;/IF NOT FOUND $2 THEN EXIT; END IF; -- apply on $1/isg;
	# Replacle call to SQL%NOTFOUND
	$str =~ s/SQL\%NOTFOUND/NOT FOUND/isg;

	# Replace REF CURSOR as Pg REFCURSOR
	$str =~ s/\bIS([\s\t]*)REF[\s\t]+CURSOR/REFCURSOR/isg;
	$str =~ s/\bREF[\s\t]+CURSOR/REFCURSOR/isg;

	# Replace SYS_REFCURSOR as Pg REFCURSOR
	$str =~ s/SYS_REFCURSOR/REFCURSOR/isg;

	# Replace known EXCEPTION equivalent ERROR code
	$str =~ s/\bINVALID_CURSOR\b/INVALID_CURSOR_STATE/igs;
	$str =~ s/\bZERO_DIVIDE\b/DIVISION_BY_ZERO/igs;
	$str =~ s/\bSTORAGE_ERROR\b/OUT_OF_MEMORY/igs;
	# PROGRAM_ERROR => INTERNAL ERROR ?
	# ROWTYPE_MISMATCH => DATATYPE MISMATCH ?

	# Replace special IEEE 754 values for not a number and infinity
	$str =~ s/BINARY_(FLOAT|DOUBLE)_NAN/'NaN'/igs;
	$str =~ s/([\-]*)BINARY_(FLOAT|DOUBLE)_INFINITY/'$1Infinity'/igs;
	$str =~ s/'([\-]*)Inf'/'$1Infinity'/igs;

	# REGEX_LIKE( string, pattern ) => string ~ pattern
	$str =~ s/REGEXP_LIKE[\s\t]*\([\s\t]*([^,]+)[\s\t]*,[\s\t]*('[^\']+')[\s\t]*\)/$1 \~ $2/igs;

	# Add the name keyword to XMLELEMENT
	$str =~ s/XMLELEMENT[\s\t]*\([\s\t]*/XMLELEMENT(name /igs;

	# Replace PIPE ROW by RETURN NEXT
	$str =~ s/PIPE[\s\t]+ROW[\s\t]*/RETURN NEXT /igs;
	$str =~ s/(RETURN NEXT )\(([^\)]+)\)/$1$2/igs;

	if ($allow_code_break) {
		# Change trunc() to date_trunc('day', field)
		# Trunc is replaced with date_trunc if we find date in the name of
		# the value because Oracle have the same trunc function on number
		# and date type
		$str =~ s/trunc\(([^\)]*date[^\)]*)\)/date_trunc('day', $1)/igs;

		# Replace Oracle substr(string, start_position, length) with
		# PostgreSQL substring(string from start_position for length)
		$str =~ s/substr[\s\t]*\(([^,\(]+),[\s\t]*([^,\s\t]+)[\s\t]*,[\s\t]*([^,\)\s\t]+)[\s\t]*\)/substring($1 from $2 for $3)/igs;
		$str =~ s/substr[\s\t]*\(([^,\(]+),[\s\t]*([^,\)\s\t]+)[\s\t]*\)/substring($1 from $2)/igs;

		# Replace decode("user_status",'active',"username",null)
		# PostgreSQL (CASE WHEN "user_status"='ACTIVE' THEN "username" ELSE NULL END)
		$str =~ s/decode[\s\t]*\([\s\t]*([^,]*),[\s\t]*([^,]*),[\s\t]*([^,]*),[\s\t]*([^\)]*)\)/\(CASE WHEN $1=$2 THEN $3 ELSE $4 END\)/igs;

		# The to_number() function reclaim a second argument under postgres which is the format.
		# By default we use '99999999999999999999D99999999999999999999' that may allow bigint
		# and double precision number. Feel free to modify it - maybe a configuration option
		# should be added
		$str =~ s/to_number[\s\t]*\([\s\t]*([a-z0-9\-\_"\.,\s]+)[\s\t]*\)/to_number\($1,'99999999999999999999D99999999999999999999'\)/igs;
	}

	return $str;
}

# Function used to rewrite dbms_output.put, dbms_output.put_line and
# dbms_output.new_line by a plpgsql code
sub raise_output
{
	my $str = shift;

	my @strings = split(/\|\|/s, $str);

	my @params = ();
	my $pattern = '';
	foreach my $el (@strings) {
		if ($el =~ /^'(.*)'$/s) {
			$pattern .= $1;
		} else {
			$pattern .= '%';
			push(@params, $el);
		}
	}
	my $ret = "RAISE NOTICE '$pattern'";
	if ($#params >= 0) {
		$ret .= ', ' . join(', ', @params);
	}

	return $ret . ';';
}

sub replace_sql_type
{
        my ($str, $pg_numeric_type, $default_numeric, $pg_integer_type) = @_;


	$str =~ s/with local time zone/with time zone/igs;
	$str =~ s/([A-Z])ORA2PG_COMMENT/$1 ORA2PG_COMMENT/igs;

	# Replace type with precision
	while ($str =~ /(.*)\b([^\s\t\(]+)[\s\t]*\(([^\)]+)\)/) {
		my $backstr = $1;
		my $type = uc($2);
		my $args = $3;
		if ($backstr =~ /_$/) {
		    $str =~ s/\b([^\s\t\(]+)[\s\t]*\(([^\)]+)\)/$1\%\|$2\%\|\%/is;
		    next;
		}

		my ($precision, $scale) = split(/,/, $args);
		$scale ||= 0;
		my $len = $precision || 0;
		if ( $type =~ /CHAR/i ) {
			# Type CHAR have default length set to 1
			# Type VARCHAR(2) must have a specified length
			$len = 1 if (!$len && (($type eq "CHAR") || ($type eq "NCHAR")));
			$str =~ s/\b$type\b[\s\t]*\([^\)]+\)/$Ora2Pg::TYPE{$type}\%\|$len\%\|\%/is;
		} elsif ($type =~ /TIMESTAMP/i) {
			$len = 6 if ($len > 6);
			$str =~ s/\b$type\b[\s\t]*\([^\)]+\)/timestamp\%\|$len%\|\%/is;
		} elsif ($type eq "NUMBER") {
			# This is an integer
			if (!$scale) {
				if ($precision) {
					if ($pg_integer_type) {
						if ($precision < 5) {
							$str =~ s/\b$type\b[\s\t]*\([^\)]+\)/smallint/is;
						} elsif ($precision <= 9) {
							$str =~ s/\b$type\b[\s\t]*\([^\)]+\)/integer/is;
						} else {
							$str =~ s/\b$type\b[\s\t]*\([^\)]+\)/bigint/is;
						}
					} else {
						$str =~ s/\b$type\b[\s\t]*\([^\)]+\)/numeric\%\|$precision\%\|\%/i;
					}
				} elsif ($pg_integer_type) {
					my $tmp = $default_numeric || 'bigint';
					$str =~ s/\b$type\b[\s\t]*\([^\)]+\)/$tmp/is;
				}
			} else {
				if ($precision) {
					if ($pg_numeric_type) {
						if ($precision <= 6) {
							$str =~ s/\b$type\b[\s\t]*\([^\)]+\)/real/is;
						} else {
							$str =~ s/\b$type\b[\s\t]*\([^\)]+\)/double precision/is;
						}
					} else {
						$str =~ s/\b$type\b[\s\t]*\([^\)]+\)/decimal\%\|$precision,$scale\%\|\%/is;
					}
				}
			}
		} elsif ($type eq "NUMERIC") {
			$str =~ s/\b$type\b[\s\t]*\([^\)]+\)/numeric\%\|$args\%\|\%/is;
		} elsif ( ($type eq "DEC") || ($type eq "DECIMAL") ) {
			$str =~ s/\b$type\b[\s\t]*\([^\)]+\)/decimal\%\|$args\%\|\%/is;
		} else {
			# Prevent from infinit loop
			$str =~ s/\(/\%\|/s;
			$str =~ s/\)/\%\|\%/s;
		}
	}
	$str =~ s/\%\|\%/\)/gs;
	$str =~ s/\%\|/\(/gs;

        # Replace datatype without precision
	my $number = $Ora2Pg::TYPE{'NUMBER'};
	$number = $default_numeric if ($pg_integer_type);
	$str =~ s/\bNUMBER\b/$number/igs;

	# Set varchar without length to text
	$str =~ s/\bVARCHAR\d*([\s\t]*(?!\())/text$1/igs;

	foreach my $t ('DATE','LONG RAW','LONG','NCLOB','CLOB','BLOB','BFILE','RAW','ROWID','FLOAT','DOUBLE PRECISION','INTEGER','INT','REAL','SMALLINT','BINARY_FLOAT','BINARY_DOUBLE','BOOLEAN','XMLTYPE') {
		$str =~ s/\b$t\b/$Ora2Pg::TYPE{$t}/igs;
	}

        return $str;
}

sub estimate_cost
{
	my $str = shift;

	# Default cost is 1 that mean it at least must be tested
	my $cost = 1;

	# Set cost following code length
	my $cost_size = int(length($str)/$SIZE_SCORE) || 1;

	$cost += $cost_size;

	# Try to figure out the manual work
	my $n = () = $str =~ m/\bFROM[\t\s]*\(/igs;
	$cost += $UNCOVERED_SCORE{'FROM'}*$n;
	$n = () = $str =~ m/\bTRUNC[\t\s]*\(/igs;
	$cost += $UNCOVERED_SCORE{'TRUNC'}*$n;
	$n = () = $str =~ m/\bDECODE[\t\s]*\(/igs;
	$cost += $UNCOVERED_SCORE{'DECODE'}*$n;
	$n = () = $str =~ m/\bIS[\t\s]+TABLE[\t\s]+OF\b/igs;
	$cost += $UNCOVERED_SCORE{'IS TABLE OF'}*$n;
	$n = () = $str =~ m/\(\+\)/igs;
	$cost += $UNCOVERED_SCORE{'OUTER JOIN'}*$n;
	$n = () = $str =~ m/\bCONNECT[\t\s]+BY\b/igs;
	$cost += $UNCOVERED_SCORE{'CONNECT BY'}*$n;
	$n = () = $str =~ m/\bBULK[\t\s]+COLLECT\b/igs;
	$cost += $UNCOVERED_SCORE{'BULK COLLECT'}*$n;
	$n = () = $str =~ m/\bFORALL\b/igs;
	$cost += $UNCOVERED_SCORE{'FORALL'}*$n;
	$n = () = $str =~ m/\bGOTO\b/igs;
	$cost += $UNCOVERED_SCORE{'GOTO'}*$n;
	$n = () = $str =~ m/\bROWNUM\b/igs;
	$cost += $UNCOVERED_SCORE{'ROWNUM'}*$n;
	$n = () = $str =~ m/\bNOTFOUND\b/igs;
	$cost += $UNCOVERED_SCORE{'NOTFOUND'}*$n;
	$n = () = $str =~ m/\bROWID\b/igs;
	$cost += $UNCOVERED_SCORE{'ROWID'}*$n;
	$n = () = $str =~ m/\bSQLSTATE\b/igs;
	$cost += $UNCOVERED_SCORE{'SQLCODE'}*$n;
	$n = () = $str =~ m/\bIS RECORD\b/igs;
	$cost += $UNCOVERED_SCORE{'IS RECORD'}*$n;
	$n = () = $str =~ m/FROM[^;]*\bTABLE[\t\s]*\(/igs;
	$cost += $UNCOVERED_SCORE{'TABLE'}*$n;
	$n = () = $str =~ m/PIPE[\t\s]+ROW/igs;
	$cost += $UNCOVERED_SCORE{'PIPE ROW'}*$n;
	$n = () = $str =~ m/DBMS_\w/igs;
	$cost += $UNCOVERED_SCORE{'DBMS_'}*$n;
	$n = () = $str =~ m/UTL_\w/igs;
	$cost += $UNCOVERED_SCORE{'UTL_'}*$n;
	$n = () = $str =~ m/CTX_\w/igs;
	$cost += $UNCOVERED_SCORE{'CTX_'}*$n;
	$n = () = $str =~ m/\bEXTRACT[\t\s]*\(/igs;
	$cost += $UNCOVERED_SCORE{'EXTRACT'}*$n;
	$n = () = $str =~ m/\bSUBSTR[\t\s]*\(/igs;
	$cost += $UNCOVERED_SCORE{'SUBSTR'}*$n;
	$n = () = $str =~ m/\bTO_NUMBER[\t\s]*\(/igs;
	$cost += $UNCOVERED_SCORE{'TO_NUMBER'}*$n;
	# See:  http://www.postgresql.org/docs/9.0/static/errcodes-appendix.html#ERRCODES-TABLE
	$n = () = $str =~ m/\b(DUP_VAL_ON_INDEX|TIMEOUT_ON_RESOURCE|TRANSACTION_BACKED_OUT|NOT_LOGGED_ON|LOGIN_DENIED|INVALID_NUMBER|PROGRAM_ERROR|VALUE_ERROR|ROWTYPE_MISMATCH|CURSOR_ALREADY_OPEN|ACCESS_INTO_NULL|COLLECTION_IS_NULL)\b/igs;
	$cost += $UNCOVERED_SCORE{'EXCEPTION'}*$n;
	$n = () = $str =~ m/REGEXP_LIKE/igs;
	$cost += $UNCOVERED_SCORE{'REGEXP_LIKE'}*$n;
	$n = () = $str =~ m/REGEXP_LIKE/igs;
	$cost += $UNCOVERED_SCORE{'REGEXP_LIKE'}*$n;
	$n = () = $str =~ m/INSERTING|DELETING|UPDATING/igs;
	$cost += $UNCOVERED_SCORE{'TG_OP'}*$n;
	$n = () = $str =~ m/CURSOR/igs;
	$cost += $UNCOVERED_SCORE{'CURSOR'}*$n;
	$n = () = $str =~ m/ORA_ROWSCN/igs;
	$cost += $UNCOVERED_SCORE{'ORA_ROWSCN'}*$n;
	$n = () = $str =~ m/SAVEPOINT/igs;
	$cost += $UNCOVERED_SCORE{'SAVEPOINT'}*$n;
	$n = () = $str =~ m/(FROM|EXEC)((?!WHERE).)*\b[\w\_]+\@[\w\_]+\b/igs;
	$cost += $UNCOVERED_SCORE{'DBLINK'}*$n;

	$n = () = $str =~ m/PLVDATE/igs;
	$cost += $UNCOVERED_SCORE{'PLVDATE'}*$n;
	$n = () = $str =~ m/PLVSTR/igs;
	$cost += $UNCOVERED_SCORE{'PLVSTR'}*$n;
	$n = () = $str =~ m/PLVCHR/igs;
	$cost += $UNCOVERED_SCORE{'PLVCHR'}*$n;
	$n = () = $str =~ m/PLVSUBST/igs;
	$cost += $UNCOVERED_SCORE{'PLVSUBST'}*$n;
	$n = () = $str =~ m/PLVLEX/igs;
	$cost += $UNCOVERED_SCORE{'PLVLEX'}*$n;
	$n = () = $str =~ m/PLUNIT/igs;
	$cost += $UNCOVERED_SCORE{'PLUNIT'}*$n;
	$n = () = $str =~ m/ADD_MONTHS/igs;
	$cost += $UNCOVERED_SCORE{'ADD_MONTHS'}*$n;
	$n = () = $str =~ m/LAST_DATE/igs;
	$cost += $UNCOVERED_SCORE{'LAST_DATE'}*$n;
	$n = () = $str =~ m/NEXT_DAY/igs;
	$cost += $UNCOVERED_SCORE{'NEXT_DAY'}*$n;
	$n = () = $str =~ m/MONTHS_BETWEEN/igs;
	$cost += $UNCOVERED_SCORE{'MONTHS_BETWEEN'}*$n;
	$n = () = $str =~ m/NVL2/igs;
	$cost += $UNCOVERED_SCORE{'NVL2'}*$n;

	return $cost;
}

1;

__END__


=head1 AUTHOR

Gilles Darold <gilles@darold.net>


=head1 COPYRIGHT

Copyright (c) 2000-2012 Gilles Darold - All rights reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.


=head1 BUGS

This perl module is in the same state as my knowledge regarding database,
it can move and not be compatible with older version so I will do my best
to give you official support for Ora2Pg. Your volontee to help construct
it and your contribution are welcome.


=head1 SEE ALSO

L<Ora2Pg>

=cut

