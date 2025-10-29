#!/bin/bash
#Designed by LLC Exactprosystems
#24.10.2023
#DevOps Engineer
#Andrei Shulika
#andrey.shulika@exactprosystems.com
#Dev	Engineer
#Nikita Smirnov
#nikita.smirnov@exactprosystems.com

log_date_time(){
	local dt=`date '+%Y-%m-%d %H:%M:%S'`
	echo ${dt}
}

if [ -z "$1" ];then
	echo "`log_date_time`: ERROR: Param 1 is empty - which mode to use? (java or python)"
	exit 2
fi

#*******Params*******
jq_path="jq"
cur_loc=`pwd`
dir="$cur_loc/licenses_check"
rm -rf $dir
mkdir -p $dir
lic_file="$dir/licenses.json"
link_allowed_licenses="https://raw.githubusercontent.com/th2-net/.github/main/license-compliance/gradle-license-report/allowed-licenses.json"
link_license_normalizer_bundle="https://raw.githubusercontent.com/th2-net/.github/main/license-compliance/gradle-license-report/license-normalizer-bundle.json"
link_info_licenses="https://raw.githubusercontent.com/th2-net/.github/main/license-compliance/gradle-license-report/info-licenses.json"

allowed_licenses="$dir/allowed-licenses.json"
normalizer_file="$dir/license-normalizer-bundle.json"
info_licenses_file="$dir/info-licenses.json"
unknown_license=""
warnings="$dir/warnings.csv"

temp_res="$dir/temp_res"
res_lic="$dir/res.lic"
report_before_check="$dir/report.csv_before_check"
failed_licenses="$dir/failed_licenses.csv"
touch $failed_licenses
passed_licenses="$dir/passed_licenses.csv"
final_report="$dir/licenses_report.csv"
head="Testing tool name,Open Source Code Library Name (contained within the Testing Tool),Version,Associated Open Source License,Comment"
echo $head > $final_report

convert_allow_lic="$dir/convert_allow_lic.csv"
convert_bom_lic="$dir/convert_bom_lic.csv"

project_name=`cat .git/config | grep "url = git@" | sed 's/\.git$//g' | awk -F "/" '{print $NF}'`
#branch=`cat .git/HEAD | awk -F '/' '{print $3}'`
branch=`git branch 2> /dev/null | egrep "\* " | sed -e 's/^* //g' | awk '{print $NF}' | sed 's/)//g'`
echo "*****************************"
echo "`log_date_time`: Project name = $project_name"
echo "`log_date_time`: Branch name = $branch"
echo "*****************************"
#******end Params*****

#Function to download file
download_file(){
	local link=$1
	local output_file=$2
	echo "`log_date_time`: Download file from $link"
	wget -q -O $output_file $link
	if [ $? -eq 0 ]; then
	        echo "`log_date_time`: Download - Completed"
	else
	        echo "`log_date_time`: ERROR: download file problem"
	        echo "`log_date_time`: Link = $link"
	        exit 2
	fi
}

#Function to check if all licenses Permissive
checkLicCategory(){
        local line=$1
        local pattern="\"[pP]ermissive\""
        local category=""
        local isPermissive=1 #1=true 0=false
        local mas=`echo $line | sed 's/ | / /g'`
        for item in $mas
        do
                local mod_item=`echo $item | sed 's/"//g' | sed 's/^/"/g' | sed 's/$/"/g'`
                category=`$jq_path --argjson n "$mod_item" '.bundles[] | select (.licenseName == $n) | .licenseCategory' $info_licenses_file`
                #echo "item = $item"
                #echo "mod_item = $mod_item"
                #echo "category = $category"

                if [[ ! "$category" =~ $pattern ]]; then
                        isPermissive=0
                fi
        done

echo ${isPermissive}
}

#Function to normalize license names
normalize(){
	local file=$1
	cp $file $file"_bkp"
	local regexp_file="$dir/regexp_file"
	local reg_sed="$dir/sed_commands_list"
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
			echo "*********************************************"
			echo "`log_date_time`: Warning"
		        echo "`log_date_time`: YOU HAVE UNDEFINED TRANSFORMATION RULE in $normalizer_file"
			echo "`log_date_time`: Regexp = $exp"
			echo "`log_date_time`: Bundle name = $bundleName"
			echo "`log_date_time`: The rule is skipped."
			echo "Undefined transformation rule,bundleName=$bundleName,regexp=$exp" >> $warnings
			echo "*********************************************"
		else
			echo "s#${mod_exp}#${lic}#g" >> $reg_sed
		fi
	done < $regexp_file
	#Apply sed commands replace patterns
	sed -f $reg_sed -i $file
	sed -i "s/ OR / | /g" $file
#	rm $reg_sed $regexp_file
}

#Download allowed-licenses.json
download_file "$link_allowed_licenses" "${allowed_licenses}"

#Download license-normalizer-bundle.json
download_file "$link_license_normalizer_bundle" "${normalizer_file}"

#Download info-licenses.json
download_file "$link_info_licenses" "${info_licenses_file}"

#Define mode and reformat files before checking
case $1 in

	java|JAVA|Java)
	echo "`log_date_time`: Using java mode"
	echo "`log_date_time`: Running gradle plugins"
	./gradlew checkLicense generateLicenseReport --info
	if [ $? -ne 0 ]; then
		echo "`log_date_time`: ERROR: check license by gradle plugin failure"
		exit 2
	fi
	cp build/reports/dependency-license/licenses.json $lic_file
	echo "`log_date_time`: Running plugins - completed"
	;;

	python|PYTHON|Python)
	echo "`log_date_time`: Using python mode"
	echo "`log_date_time`: Running pip-licenses"
	pip install 'pip-licenses>=5.5.0'
	pip-licenses --format=json --from=all --output-file=pyth_licenses.json
	#Reformat to common
	jq '
	{
		dependencies: [
		.[] |
		{
			moduleName: .Name,
			moduleVersion: .Version,
			moduleLicenses: [
			{
				moduleLicense:
				(
					(.["License-Classifier"] | select(. != "UNKNOWN" and . != "")) //
					(.["License-Expression"] | select(. != "UNKNOWN" and . != "")) //
					(.["License-Metadata"] | select(. != "UNKNOWN" and . != "")) //
                	"UNKNOWN"
				)
			}
			] | map(select(.moduleLicense != null))
		}
		]
	}
	' pyth_licenses.json > "${lic_file}"
  	mv pyth_licenses.json "${dir}"
	normalize "${lic_file}"
	echo "`log_date_time`: Running pip-licenses - completed"
	;;

	go|golang|GO|GOLANG)
	echo "`log_date_time`: Using golang mode"
	echo "`log_date_time`: Running go-licenses"
	go install github.com/google/go-licenses/v2@latest
	go-licenses csv ./... > licenses.csv
	go_allowed_licenses=$(jq -r '.bundles[].licenseName' "${normalizer_file}" | paste -sd ',')
	echo "`log_date_time`: allowed licenses [${go_allowed_licenses}]"
	go-licenses check ./... --allowed_licenses="${go_allowed_licenses}"
	if [ $? -ne 0 ]; then
		echo "`log_date_time`: ERROR: check license by go-licenses tool failure"
		exit 2
	fi
	jq -Rn '
	[inputs | . / "\n" | map(select(length > 0))[] |
		split(",") |
		{
		moduleLicenses: [{moduleLicense: .[2]}],
		moduleName: .[0],
		moduleVersion: (.[1] | capture("/blob/(?<v>[^/]+)/LICENSE").v)
		}
	] | {dependencies: .}
	' < licenses.csv > "${lic_file}"
	mv licenses.csv "${dir}"
	normalize "${lic_file}"
	echo "`log_date_time`: Running go-licenses - completed"
	;;

	*)
	echo "`log_date_time`: Unknown mode"
	exit 2
	;;
esac


echo "`log_date_time`: Parsing file $lic_file"

#Make report prior to check
#Old version without URLs
#$jq_path -r '.dependencies[] | .licenses = try (.moduleLicenses[].moduleLicense) catch "null" | [.moduleName, .moduleVersion, .licenses ] | @csv' $lic_file | sort -u > $temp_res

#Filter rubbish `"moduleLicense": "LICENSE"`
#Old version without filter
#$jq_path -r '.dependencies[] | [.moduleName, .moduleVersion, try (.moduleLicenses[].moduleLicense) catch "null", try (.moduleLicenses[].moduleLicenseUrl) catch "null"] | @csv' $lic_file | sort -u > $temp_res

$jq_path -r '.dependencies[] | .moduleLicenses |= map(select(.moduleLicense != "LICENSE")) | [.moduleName, .moduleVersion, try (.moduleLicenses[].moduleLicense) catch "null", try (.moduleLicenses[].moduleLicenseUrl) catch "null"] | @csv' $lic_file | sort -u > $temp_res

echo "`log_date_time`: Forming report"

for main in `cat $temp_res | tr ' ' ';'`
    do
        name=`echo $main | awk -F "," '{print $1}'`
        version=`echo $main | awk -F "," '{print $2}'`
        lic=""
	lic_url=""
	#echo "Head = $name , $version"

	#Concatenate strings if licenses more than one via vertical line |
        for line in `cat $temp_res | tr ' ' ';' | grep $name | grep $version`
            do
		#echo "Line = $line"
		column_number=`echo $line | awk -F "," '{print NF}'`
		#echo "Column number = $column_number"
		if [ "$column_number" -gt 4 ]
		then
			for (( col=3; col < $column_number+1; col++ ))
			do
				#echo "Col = $col"
				item=`echo $line | awk -v num=$col -F "," '{print $num}'`
				reg_exp="^[\"|;]?http" #to find links starts from http
				#echo "Reg = $reg_exp"
				#echo "item = $item"
				if [[ "$item" =~ $reg_exp ]]
				then
					if [[ $lic_url == "" ]]
					then
						lic_url=$item
					else
						lic_url=$lic_url" | "$item
					fi
				else
					# trim ; (former space) from start and end of the item
					item=${item#;}
					item=${item%;}
					if [[ $item != '""' ]]
					then
						if [[ $lic == "" ]]
						then
						lic=$item
						else
						lic=$lic" | "$item
						fi
					fi
				fi
			done
		else
			if [[ "$lic" == "" ]]
			then
				lic=`echo $line | awk -F "," '{print $3}'`
				lic_url=`echo $line | awk -F "," '{print $4}'`
			else
		    lic=$lic" | "`echo $line | awk -F "," '{print $3}'`
				lic_url=$lic_url" | "`echo $line | awk -F "," '{print $4}'`
			fi
		fi
#		echo "Lic = $lic"
#		echo "Lic url = $lic_url"
#		echo "***************************"
            done

#	echo "Head = $name , $version"
#       echo "Lic = $lic"
#       echo "Lic url = $lic_url"
#	echo "***************************"
	lic=`echo $lic | sed 's/"//g' | sed 's/^/"/g' | sed 's/$/"/g'`
	lic_url=`echo $lic_url | sed 's/"//g' | sed 's/^/"/g' | sed 's/$/"/g'`
        echo "$name,$version,$lic,$lic_url" | tr ';' ' ' >> $res_lic
	lic=""
	lic_url=""
	#echo "-----------------------"
    done

cat $res_lic | sort -u > $report_before_check

#rm $res_lic $temp_res
echo "`log_date_time`: Forming completed"


#regular expressions from allowed-licenses.json
$jq_path -r '.allowedLicenses[] | .moduleLicense' $allowed_licenses | grep -v null | sort -u > $convert_allow_lic

#bom lines from allowed-licenses.json
$jq_path -r '.allowedLicenses[] | .licenses = try (.mvnRepositoryLicense) catch "null" | [.moduleName, .moduleVersion, .licenses ] | @csv' $allowed_licenses | sort -u | grep -v ",," | sed 's/"//g' > $convert_bom_lic


#Check license based on regular expressions in allowed-licenses.json file
echo "`log_date_time`: Checking licenses"
echo "--------------------------------------"

while IFS=, read -r name version license url
do
	lic_category=""
	known_license=0 #0 = false
        ORchange=`echo $license | sed 's/"//g'`
        mod_license=`echo $ORchange | sed 's/ | / OR /g'`

	if [[ "$mod_license" != "null" && "$mod_license" != "UNKNOWN" ]]; then
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


	#Getting info about license category
	mod_license=`echo $license | sed 's/ | / OR /g'` #modify to find multilicense items
	lic_category=`$jq_path --argjson n "$mod_license" '.bundles[] | select (.licenseName == $n) | .licenseCategory' $info_licenses_file`

        num=`echo "$license" | awk -F " | " '{print NF}'`
        if [ $num -ge 2 ]; then
                #echo "Checking composite license..."
                #Example if license = "MIT | MPL-2.0" then check
                check=`checkLicCategory "$license"`
                if [ $check -eq 1 ]; then
                        lic_category="\"Permissive\""
                fi
        fi

        if [ "$url" == "\"\"" ]; then
                url=`$jq_path --argjson n "$mod_license" '.bundles[] | select (.licenseName == $n) | .licenseUrl' $normalizer_file | sed 's/ OR / | /g'`
        fi

	#echo "Project name = $project_name"
	#echo "Branch = $branch"
        #echo "Name = $name"
        #echo "Version = $version"
        #echo "License = $license"
        #echo "Url = $url"
        #echo "licenseCategory = $lic_category"

        if [ "$known_license" -eq 0 ]; then
               echo "`log_date_time`: Line = $name,$version,$license"
               echo "`log_date_time`: Result = ***FAILED***"
               echo "\"$project_name/$branch\",$name,$version,$license,$url,$lic_category" >> $failed_licenses
               echo "--------------------------------------"
        else
               echo "\"$project_name/$branch\",$name,$version,$license,$url,$lic_category" >> $passed_licenses
	       #echo "Result = *PASSED*"
        fi
	echo "\"$project_name/$branch\",$name,$version,$license,$url,$lic_category" >> $final_report
	#echo "--------------------------------------------------------------"

done < $report_before_check

echo "`log_date_time`: CHECK LICENSES - COMPLETED. PLEASE SEE REPORTS WITH DETAILS."
echo "Folder = $dir"
echo "Passed report = $passed_licenses"
echo "Failed report = $failed_licenses"
echo "Final report = $final_report"