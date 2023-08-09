#!/bin/bash

if [ -z "$1" ];then
	echo "ERROR: Param 1 is empty - which mode to use? (java or python)"
	exit 2
fi

#*******Params*******
jq_path="/home/exp.exactpro.com/andrey.shulika/DEVOPS/work/soft/jq/jq-linux64"
dir="licenses_check"
mkdir -p $dir
#rm -rf $dir
lic_file="$dir/licenses.json"

link_allowed_licenses="https://raw.githubusercontent.com/th2-net/.github/th2-1836-json-files-update/license-compliance/gradle-license-report/allowed-licenses.json"
link_license_normalizer_bundle="https://raw.githubusercontent.com/th2-net/.github/th2-1836-json-files-update/license-compliance/gradle-license-report/license-normalizer-bundle.json"
allowed_licenses="$dir/allowed-licenses.json"
unknown_license=""
warnings="$dir/warnings.csv"

temp_res="$dir/temp_res"
res_lic="$dir/res.lic"
report_before_check="$dir/report.csv_before_check"
failed_licenses="$dir/failed_licenses.csv"
passed_licenses="$dir/passed_licenses.csv"
final_report="$dir/licenses_report.csv"
head="Testing tool name,Open Source Code Library Name (contained within the Testing Tool),Version,Associated Open Source License,Comment"
echo $head > $final_report

convert_allow_lic="$dir/convert_allow_lic.csv"
convert_bom_lic="$dir/convert_bom_lic.csv"
#******end Params*****

#Function to download file
download_file(){
	local link=$1
	local output_file=$2
	echo "Download file from $link"
	wget -q -O $output_file $link
	if [ $? -eq 0 ]; then
	        echo "Download - Completed"
	else
	        echo "ERROR: download file problem"
	        echo "Link = $link"
	        exit 2
	fi
}

#Function to normalize license names
normalize(){
	local file=$1
	cp $file $file"_bkp"
	local regexp_file="$dir/regexp_file"
	local normalizer_file="$dir/license-normalizer-bundle.json"
	local reg_sed="$dir/sed_commands_list"
	download_file "$link_license_normalizer_bundle" "$normalizer_file"

	#Prepare regexp file format bundleName,regexp
	$jq_path -r '.transformationRules[] | .lic = (.licenseNamePattern // .licenseUrlPattern) | [ .bundleName, .lic ] | @csv' $normalizer_file > $regexp_file

	#Prepare sed commands to apply to initial file to replace known pattern to normal license name
	while IFS= read -r line
	do
		local bundleName=`echo $line | awk -F "\",\"" '{print $1}' | sed 's/"//g'`
		local exp=`echo $line | awk -F "\",\"" '{print $2}' | sed 's/"//g'`
		local mod_exp=`echo $exp | sed 's/\\\//g' | sed 's/\^/"/g' | sed 's/\\$/"/g'`
		#Find lic name that need to be applied instead of text
		local lic=`$jq_path -r '.bundles[] | select (.bundleName == "'$bundleName'") | .licenseName' $normalizer_file | sed 's/^/"/g' | sed 's/$/"/g'`
		#echo "Exp = $exp"
		#echo "Mod_exp = $mod_exp"
                #echo "BundleName = $bundleName"
		#echo "Lic = $lic"
		if  [[  -z $lic  ]]; then
			echo "***************WARNING***************"
		        echo "YOU HAVE UNDEFINED TRANSFORMATION RULE in $normalizer_file"
			echo "Regexp = $exp"
			echo "Bundle name = $bundleName"
			echo "The rule is skipped."
			echo "Undefined transformation rule,bundleName=$bundleName,regexp=$exp" >> $warnings
			echo "*************************************"
		else
			echo "s#${mod_exp}#${lic}#g" >> $reg_sed
		fi
	done < $regexp_file
	#Apply sed commands replace patterns
	sed -f $reg_sed -i $file
#	rm $reg_sed $regexp_file
}




#Define mode and reformat files before checking
case $1 in

	java|JAVA|Java)
	echo "Using java mode"
	echo "Running gradle plugins"
	./gradlew checkLicense generateLicenseReport
	cp build/reports/dependency-license/licenses.json $lic_file
	echo "Running plugins - completed"
	;;

	python|PYTHON|Python)
	echo "Using python mode"
	echo "Running pip-licenses"
	pip install pip-licenses
	pip-licenses --format=json --output-file=pyth_licenses.json
	#Reformat to common
	cat pyth_licenses.json | sed 's/^\[/\{ "dependencies": \[/g' | sed 's/^\]/\] \}/g' > p_temp
	cat p_temp | sed 's/"Name"/"moduleName"/g' | sed 's/"Version"/"moduleVersion"/g' | sed 's/\("License":\)\( ".*"\)/"moduleLicenses": \[ \{ "moduleLicense": \2 \} \]/g' > pyth_licenses.json
	rm p_temp
	mv pyth_licenses.json $lic_file
	normalize "$lic_file"
	echo "Running pip-licenses - completed"
	;;

	*)
	echo "Unknown mode"
	exit 2
	;;
esac

#*******Params*******

link_allowed_licenses="https://raw.githubusercontent.com/th2-net/.github/th2-1836-json-files-update/license-compliance/gradle-license-report/allowed-licenses.json"
allowed_licenses="$dir/allowed-licenses.json"
unknown_license=""

temp_res="$dir/temp_res"
res_lic="$dir/res.lic"
report_before_check="$dir/report.csv_before_check"
failed_licenses="$dir/failed_licenses.csv"
passed_licenses="$dir/passed_licenses.csv"
final_report="$dir/licenses_report.csv"
head="Testing tool name,Open Source Code Library Name (contained within the Testing Tool),Version,Associated Open Source License,Comment"
echo $head > $final_report

convert_allow_lic="$dir/convert_allow_lic.csv"
convert_bom_lic="$dir/convert_bom_lic.csv"
#******end Params*****

echo "Parsing file $lic_file"

#Make report prior to check
$jq_path -r '.dependencies[] | .licenses = try (.moduleLicenses[].moduleLicense) catch "null" | [.moduleName, .moduleVersion, .licenses ] | @csv' $lic_file | sort -u > $temp_res

echo "Forming report"

for main in `cat $temp_res | tr ' ' ';'`
    do
        name=`echo $main | awk -F "," '{print $1}'`
        version=`echo $main | awk -F "," '{print $2}'`
        lic=""
	#echo "Head = $name , $version"
        for line in `cat $temp_res | tr ' ' ';' | grep $name`
            do
		#echo "Line = $line"
		if [[ "$lic" == "" ]]
		then
			lic=`echo $line | awk -F "," '{print $3}'`
		else
	                lic=$lic" | "`echo $line | awk -F "," '{print $3}'`
		fi
		#echo "Lic = $lic"
            done
	lic=`echo $lic | sed 's/"//g' | sed 's/^/"/g' | sed 's/$/"/g'`
        echo $name,$version,$lic | tr ';' ' ' >> $res_lic
	lic=""
	#echo "-----------------------"
    done

cat $res_lic | sort -u > $report_before_check

rm $res_lic $temp_res
echo "Forming completed"


#Download allowed-licenses.json
echo "Download allowed-licenses file"
download_file "$link_allowed_licenses" "$allowed_licenses"


#simple text
#Reformat allowed-licenses
#/home/exp.exactpro.com/andrey.shulika/DEVOPS/work/soft/jq/jq-linux64 -r '.allowedLicenses[] | .moduleLicense' $allowed_licenses | sed 's/\^//g' | sed 's/\$//g' | sed 's/\\//g' | grep -v null | sort -u > $convert_allow_lic

#regular expressions
$jq_path -r '.allowedLicenses[] | .moduleLicense' $allowed_licenses | grep -v null | sort -u > $convert_allow_lic

$jq_path -r '.allowedLicenses[] | .licenses = try (.mvnRepositoryLicense) catch "null" | [.moduleName, .moduleVersion, .licenses ] | @csv' $allowed_licenses | sort -u | grep -v ",," | sed 's/"//g' > $convert_bom_lic


#Check license based on regular expressions in allowed-licenses.json file
echo "Checking licenses"

while IFS=, read -r name version license
do
	#echo "Name = $name"
	#echo "Version = $version"
	#echo "License = $license"
	known_license=0 #0 = false
	mod_license=`echo $license | sed 's/"//g'`

	if [[ "$mod_license" != "null" ]]; then
		while IFS= read -r exp
		do
		exp=`echo $exp | sed 's/|/\\\|/g'` #escape vertical line in expression
		#echo "Exp = $exp"
		if [[ $mod_license =~ $exp ]]; then
		  #echo "Passed"
		  known_license=1 #1 = true
		  break;
		fi
		done < $convert_allow_lic
	else # if license == null
		mod_name=`echo $name | sed 's/"//g'`
		mod_ver=`echo $version | sed 's/"//g'`
		#echo "Mod_name = $mod_name"
		#echo "Mod_ver = $mod_ver"
		while IFS=, read -r c_name c_ver c_lic
		do
			#echo "C_name = $c_name"
			c_ver=`echo $c_ver | sed 's/\\\d/[0-9]/g'` #replace \d to [0-9] in regular expressions to apply in bash according to POSIX
			#echo "C_ver = $c_ver"
			#echo "C_lic = $c_lic"

			if [[ $mod_name =~ $c_name ]]; then
				if [[ $mod_ver =~ $c_ver ]]; then
					known_license=1
					license=`echo $c_lic | sed 's/^/"/g' | sed 's/$/"/g'`
					break;
				fi
			fi
		done < $convert_bom_lic
	fi


        if [ "$known_license" -eq 0 ]; then
               echo "Line = $name,$version,$license"
               echo "Result = ***FAILED***"
               echo "$name,$version,$license" >> $failed_licenses
               echo "--------------------------------------"
        else
               echo "$name,$version,$license" >> $passed_licenses
	       #echo "Result = *PASSED*"
        fi
	`echo ",$name,$version,$license" >> $final_report`
	#echo "--------------------------------------------------------------"

done < $report_before_check

echo "CHECK LICENSES - COMPLETED. PLEASE SEE REPORTS WITH DETAILS."
echo "Folder = $dir"
echo "Passed report = $passed_licenses"
echo "Failed report = $failed_licenses"
echo "Final report = $final_report"




#Old code - comparing based on text
#Check license
#echo "Checking licenses"
#for line in `cat $report_before_check | tr ' ' ';'`
#do
#	item=`echo $line | awk -F "," '{print $3}' | tr ';' ' ' | sed 's/"//g'`
#	known_license=0 #0 = false
#	#echo "Item = $item"
#
#	if [[ "$item" != "null" ]]; then
#		for lic_line in `cat $allowed_licenses | awk -F "," '{print $1}' | tr ' ' ';'`
#		do
#			#echo "License line = $lic_line"
#			lic="`echo $lic_line | tr ';' ' ' | sed 's/ | /|/g'`"
#			#echo "Lic = $lic"
#			if [[ "$item" == "$lic" ]]; then
#				known_license=1 # 1 - true
#				#echo "Result = PASSED"
#				break;
#			fi
#		done
#	fi
#
#	if [ "$known_license" -eq 0 ]; then
#		echo "Line = $line "
#		echo "Result = ***FAILED***"
#		`echo "$line" | tr ';' ' ' >> $failed_licenses`
#		echo "-----------------------"
#	else
#		`echo "$line" | tr ';' ' ' >> $passed_licenses`
#	fi
#done
#end old code
