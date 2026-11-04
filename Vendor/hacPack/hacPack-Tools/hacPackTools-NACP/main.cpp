#include <iostream>
#include <string>
#include <cstdlib>
#include <getopt.h>
#include "nacp.hpp"
#include "settings.hpp"

using namespace std;

// hacPackTools-NACP by The-4n

void usage()
{
    cerr << "Usage: " << USAGE_PROGRAM_NAME << " [options...]\n\n"
                                               "Options:\n"
                                               "-a, --action             print, createnacp, createxml\n"
                                               "-i, --input              Input file\n"
                                               "-o, --output             Output file\n"
                                               "-h, --help               Display usage\n";
    exit(EXIT_FAILURE);
}

int main(int argc, char *argv[])
{
    nacp_tool tool;
    string input_filepath;
    string output_filepath;
    enum action_arg
    {
        none,
        print,
        createnacp,
        createxml
    };
    action_arg action = none;

    cout << "hacPackTools-NACP " << HPTNACP_VERSION << " by The-4n\n";

    // Parse options
    while (1)
    {
        int option_index;
        int c;
        static struct option long_options[] =
            {
                {"action", 1, NULL, 'a'},
                {"input", 1, NULL, 'i'},
                {"output", 1, NULL, 'o'},
                {"help", 0, NULL, 'h'},
                {NULL, 0, NULL, 0},
            };

        c = getopt_long(argc, argv, "a:i:o:h", long_options, &option_index);
        if (c == -1)
            break;

        switch (c)
        {
        case 'a':
            if (string(optarg).compare("print") == 0)
                action = print;
            else if (string(optarg).compare("createnacp") == 0)
                action = createnacp;
            else if (string(optarg).compare("createxml") == 0)
                action = createxml;
            else
                usage();
            break;
        case 'i':
            input_filepath = string(optarg);
            break;
        case 'o':
            output_filepath = string(optarg);
            break;
        case 'h':
            usage();
            break;
        default:
            usage();
        }
    }

    cout << "\n";

    switch (action)
    {
    case print:
        if (!input_filepath.empty())
            tool.print(&input_filepath);
        else
        {
            cerr << "Input filepath is empty\n";
            usage();
        }
        break;
    case createnacp:
        if (input_filepath.empty())
        {
            cerr << "Input filepath is empty\n";
            usage();
        }
        else if (output_filepath.empty())
        {
            cerr << "Output filepath is empty\n";
            usage();
        }
        else
            tool.createnacp(&input_filepath, &output_filepath);
        break;
    case createxml:
        if (input_filepath.empty())
        {
            cerr << "Input filepath is empty\n";
            usage();
        }
        else if (output_filepath.empty())
        {
            cerr << "Output filepath is empty\n";
            usage();
        }
        else
            tool.createxml(&input_filepath, &output_filepath);
        break;
    default:
        usage();
    }

    return 0;
}