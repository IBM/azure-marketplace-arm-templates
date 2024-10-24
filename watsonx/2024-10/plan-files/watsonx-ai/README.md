# Plan files

This folder contains the files that are uploaded to the Azure marketplace.

The main files are,

## mainTemplate.json

This file contains the ARM Template that is executed by the Azure marketplace.

## createUiDefinition.json

This is the user interface definition that is run by the Azure marketplace to collect the parameters for the ARM Template.

## *.zip

The zip file contains the mainTemplate.json and createUiDefinition.json. It is loaded into the Azure marketplace plan via the customer portal.