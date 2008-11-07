//
//  PageDetailViewController.h
//  WordPress
//
//  Created by Janakiram on 01/11/08.
//  Copyright 2008 Prithvi Information Solutions Limited. All rights reserved.
//

#import <UIKit/UIKit.h>
@class WPNavigationLeftButtonView;
@class WPSelectionTableViewController;
@class PageDetailsController;
@class WPPhotosListViewController;
@interface PageDetailViewController : UIViewController<UIActionSheetDelegate>  {
	IBOutlet UITextView *textView;
	IBOutlet UITextField *titleTextField;
	IBOutlet UIView *contentView;
	IBOutlet UIView *subView;
	IBOutlet UITextField *statusTextField;
	IBOutlet UITextField *categoriesTextField;
	IBOutlet UILabel *statusLabel;
	IBOutlet UILabel *categoriesLabel;
	IBOutlet UILabel *titleLabel;
	IBOutlet UIView *textViewContentView;
	IBOutlet UITextField *textViewPlaceHolderField;
	WPSelectionTableViewController *selectionTableViewController;
	PageDetailsController *pageDetailsController;
	
	WPPhotosListViewController *photosListController;


	int mode;	//0 new, 1 edit, 2 autorecovery, 3 refresh
	BOOL hasChanges;
	BOOL isTextViewEditing;
}

@property (nonatomic, retain) PageDetailsController *pageDetailsController;
@property (nonatomic, retain) WPSelectionTableViewController *selectionTableViewController;
@property (nonatomic)	int mode;
@property (nonatomic,assign) WPPhotosListViewController *photosListController;

- (void)refreshUIForCurrentPage;
- (IBAction)showStatusViewAction:(id)sender;
- (void)endEditingAction:(id)sender;
- (void)refreshUIForCurrentPage;
- (void)refreshUIForNewPage;
@end
