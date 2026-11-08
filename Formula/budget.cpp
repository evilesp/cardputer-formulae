// budget: your money in a text file. Each line of the file is DATE;CATEGORY;AMOUNT;NOTE.
//   budget add 12.50 food "lunch" [2026-11-08]
//   budget list [CATEGORY]
//   budget report            sums per category and per month
//   budget del NUMBER
// The file is ~/.budget, or the one named in BUDGET_FILE.
#include <algorithm>
#include <cstdlib>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>
using namespace std;

struct Entry {
    string date;
    string category;
    double amount;
    string note;
};

class Book {
public:
    explicit Book(const string& path) : path_(path) { load(); }

    void add(const Entry& e) {
        entries_.push_back(e);
        sort(entries_.begin(), entries_.end(), [](const Entry& a, const Entry& b) { return a.date < b.date; });
        save();
    }

    bool remove(int number) {
        if (number < 1 || number > (int)entries_.size()) return false;
        entries_.erase(entries_.begin() + (number - 1));
        save();
        return true;
    }

    void list(const string& category) const {
        double total = 0;
        int n = 0;
        for (const Entry& e : entries_) {
            n++;
            if (!category.empty() && e.category != category) continue;
            cout << setw(3) << n << "  " << e.date << "  " << left << setw(10) << e.category << right << setw(10) << fixed << setprecision(2) << e.amount << "  " << e.note << "\n";
            total += e.amount;
        }
        cout << "total " << fixed << setprecision(2) << total << "\n";
    }

    void report() const {
        map<string, double> byCategory;
        map<string, double> byMonth;
        double total = 0;
        for (const Entry& e : entries_) {
            byCategory[e.category] += e.amount;
            byMonth[e.date.substr(0, 7)] += e.amount;
            total += e.amount;
        }
        cout << "per category\n";
        vector<pair<string, double>> rows(byCategory.begin(), byCategory.end());
        sort(rows.begin(), rows.end(), [](const pair<string, double>& a, const pair<string, double>& b) { return a.second > b.second; });
        for (const auto& r : rows) {
            int bar = total > 0 ? (int)(r.second * 20 / total + 0.5) : 0;
            cout << "  " << left << setw(10) << r.first << right << setw(10) << fixed << setprecision(2) << r.second << " " << string(bar, '#') << "\n";
        }
        cout << "per month\n";
        for (const auto& m : byMonth) {
            cout << "  " << m.first << "  " << setw(10) << fixed << setprecision(2) << m.second << "\n";
        }
        cout << "total " << fixed << setprecision(2) << total << " in " << entries_.size() << " entries\n";
    }

private:
    string path_;
    vector<Entry> entries_;

    void load() {
        ifstream in(path_);
        string line;
        while (getline(in, line)) {
            if (line.empty()) continue;
            stringstream ss(line);
            Entry e;
            string amount;
            getline(ss, e.date, ';');
            getline(ss, e.category, ';');
            getline(ss, amount, ';');
            getline(ss, e.note);
            e.amount = atof(amount.c_str());
            entries_.push_back(e);
        }
    }

    void save() const {
        ofstream out(path_);
        for (const Entry& e : entries_) {
            out << e.date << ";" << e.category << ";" << fixed << setprecision(2) << e.amount << ";" << e.note << "\n";
        }
    }
};

static string today() {
    time_t t = time(nullptr);
    struct tm* tm = localtime(&t);
    char buf[16];
    strftime(buf, sizeof buf, "%Y-%m-%d", tm);
    return buf;
}

static void usage() {
    cout << "usage: budget add AMOUNT CATEGORY [NOTE] [DATE] | list [CATEGORY] | report | del NUMBER\n";
}

int main(int argc, char** argv) {
    const char* env = getenv("BUDGET_FILE");
    string path = env ? env : string(getenv("HOME") ? getenv("HOME") : ".") + "/.budget";
    Book book(path);
    string cmd = argc > 1 ? argv[1] : "report";
    if (cmd == "add" && argc >= 4) {
        Entry e;
        e.amount = atof(argv[2]);
        e.category = argv[3];
        e.note = argc > 4 ? argv[4] : "";
        e.date = argc > 5 ? argv[5] : today();
        book.add(e);
        cout << "added " << fixed << setprecision(2) << e.amount << " to " << e.category << "\n";
    } else if (cmd == "list") {
        book.list(argc > 2 ? argv[2] : "");
    } else if (cmd == "report") {
        book.report();
    } else if (cmd == "del" && argc == 3) {
        if (!book.remove(atoi(argv[2]))) {
            cerr << "budget: no such entry\n";
            return 1;
        }
        cout << "removed\n";
    } else {
        usage();
        return cmd == "help" || cmd == "--help" ? 0 : 2;
    }
    return 0;
}
