//
//  3DMapViewController.m
//  EDDiscovery
//
//  3D Views by Hamish Marson <hamish@travellingkiwi.com> 10/07/2016
//  Copyright © 2016 Hamish Marson. All rights reserved.
//
//  Based on Apple MetalRenderer example

//#import <UIImage.h>
#import <QuartzCore/CAMetalLayer.h>
#import <simd/simd.h>
#include <stdio.h>

#import "ThreeDMapViewController.h"
#import "Jump.h"
#import "Commander.h"
#import "System.h"
#import "CartographicOverlayRenderer.h"
#import "CartographicOverlay.h"
#import "MapAnnotation.h"
#import "BlackTileOverlay.h"
#import "ThreeDMapView.h"
#import "ThreeDMapRenderer.h"
#import "backLoader.h"


//boundaries of galaxy, in ED coordinate system

#define MINX -45000
#define MAXX  45000
#define MINY -20000
#define MAXY  70000

#define H3D_READ_STATIONS
#define DRAWGALAXY

@implementation ThreeDMapViewController {
@private
  // app control
  CVDisplayLinkRef _displayLink;
  dispatch_source_t _displaySource;
  
  // boolean to determine if the first draw has occured
  BOOL _firstDrawOccurred;
  
  CFTimeInterval _timeSinceLastDrawPreviousTime;
  
  // pause/resume
  BOOL _gameLoopPaused;
  
  // our renderer instance
  ThreeDMapRenderer *_renderer;

  galaxy_t galaxy;
  
  backLoader *bload;
  
}

- (void)dealloc {
  if(_displayLink) {
    [self stopGameLoop];
  }
}

// This is the renderer output callback function
static CVReturn dispatchGameLoop(CVDisplayLinkRef displayLink,
                                 const CVTimeStamp* now,
                                 const CVTimeStamp* outputTime,
                                 CVOptionFlags flagsIn,
                                 CVOptionFlags* flagsOut,
                                 void* displayLinkContext) {
  __weak dispatch_source_t source = (__bridge dispatch_source_t)displayLinkContext;
  dispatch_source_merge_data(source, 1);
  return kCVReturnSuccess;
}

- (void)initCommon {
  _renderer = [ThreeDMapRenderer new];
  self.delegate = _renderer;
  
  _displaySource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, dispatch_get_main_queue());
  __block ThreeDMapViewController* weakSelf = self;
  dispatch_source_set_event_handler(_displaySource, ^(){
    [weakSelf gameloop];
  });
  dispatch_resume(_displaySource);
  
  CVReturn cvReturn;
  // Create a display link capable of being used with all active displays
  cvReturn = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
  
  assert(cvReturn == kCVReturnSuccess);
  
  cvReturn = CVDisplayLinkSetOutputCallback(_displayLink, &dispatchGameLoop, (__bridge void*)_displaySource);
  
  assert(cvReturn == kCVReturnSuccess);
  
  cvReturn = CVDisplayLinkSetCurrentCGDisplay(_displayLink, CGMainDisplayID () );
  
  assert(cvReturn == kCVReturnSuccess);
  
  _interval = 1;
}

- (void)_windowWillClose:(NSNotification*)notification {
  // Stop the display link when the window is closing because we will
  // not be able to get a drawable, but the display link may continue
  // to fire
  
  if(notification.object == self.view.window) {
    CVDisplayLinkStop(_displayLink);
    dispatch_source_cancel(_displaySource);
  }
}

- (id)init {
  self = [super init];
  
  if(self) {
    [self initCommon];
  }
  return self;
}

// Called when loaded from nib
- (id)initWithNibName:(NSString *)nibNameOrNil
               bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil
                         bundle:nibBundleOrNil];
  
  if(self) {
    [self initCommon];
  }
  
  return self;
}

// called when loaded from storyboard
- (id)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  
  if(self) {
    [self initCommon];
  }
  
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  
  NSLog(@"%s:", __FUNCTION__);

  ThreeDMapView *renderView = (ThreeDMapView *)self.view;
  renderView.delegate = _renderer;
  
  // load all renderer assets before starting game loop
  [_renderer configure:renderView galaxy:&galaxy];
  
  
  NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
  // Register to be notified when the window closes so we can stop the displaylink
  [notificationCenter addObserver:self
                         selector:@selector(_windowWillClose:)
                             name:NSWindowWillCloseNotification
                           object:self.view.window];
  
  
  CVDisplayLinkStart(_displayLink);
  
}

- (void)viewDidAppear {
  [super viewDidAppear];
  
  [Answers logCustomEventWithName:@"Screen view" customAttributes:@{@"screen":NSStringFromClass(self.class)}];
  
  [self loadGalaxy];
  
  [_renderer reshape:self.view];
  
  [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(loadJumpsAndWaypoints) name:NEW_JUMP_NOTIFICATION object:nil];
  
  bload=[backLoader new];
  
  [bload startEDDB:&galaxy];
}

- (void)viewDidDisappear {
  [super viewDidDisappear];
  
  [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self name:NEW_JUMP_NOTIFICATION object:nil];
}

#pragma mark -
#pragma mark ED coordinate system

- (void)loadCoordinateSystem {
  //determine boundaries of map view, in map view coordinate format

  
  
  
  
}

text_block_t *createLabel(NSString *text) {
  unsigned long width, height;
  
#if 0
  UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, 0.0);
  CIImage *blank = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
#endif
  
  return NULL;
}

//
// All this loading should be done by a thread in the background. So we
//   a. Update automatically as things go along
//   b. Don't pause the program to load the humoungous amounts of data
//
- (void)loadJumpsAndWaypoints {
  NSArray         *jumps  = [Jump allJumpsOfCommander:Commander.activeCommander];
  journey_block_t *journey=galaxy.first_journey_block;
  
  // If the jumps are not null... We need to refresh them...
  journey_block_t *jb=galaxy.first_journey_block;
  while(jb!=NULL) {
    journey_block_t *dj=jb;
    jb=jb->next;
    dj->next=NULL;
    
    free(dj);
  }
  galaxy.first_journey_block=NULL;
  galaxy.last_journey_block=NULL;
  
  JourneyVertex_t *point=NULL;
  for (Jump *jump in jumps) {
    if (jump.system.hasCoordinates) { // && !jump.hidden) {
      if(journey==NULL) {
        //NSLog(@"%s: journey is NULL - allocating %lu bytes for new one", __FUNCTION__, sizeof(journey_block_t));
        
        if((journey=calloc(sizeof(journey_block_t), 1))==NULL) {
          NSLog(@"%s: Unable to calloc %lu Bytes for journey_block_t", __FUNCTION__, sizeof(journey_block_t));
          exit(-1);
        }
        
        journey->prev=galaxy.last_journey_block;
        journey->next=NULL;
        if(galaxy.first_journey_block==NULL) {
          galaxy.first_journey_block=journey;
        }
        if(galaxy.last_journey_block!=NULL) {
          galaxy.last_journey_block->next=journey;
        }
        
        galaxy.last_journey_block=journey;
        
        galaxy.num_journey_blocks++;
      }

      point=&journey->systems[journey->numsystems];
      
      point->posx = jump.system.x/LY_2_MTL;
      point->posy = jump.system.y/LY_2_MTL;
      point->posz = jump.system.z/LY_2_MTL;
      
      NSLog(@"%s: Jump Point %d (%@) BLOCK %d BLI %d (%8.4f %8.4f %8.4f)", __FUNCTION__, galaxy.total_journey_points, jump.system.name, galaxy.num_journey_blocks, galaxy.total_journey_points, point->posx, point->posy, point->posz);
  
      galaxy.total_journey_points++;
      
      if(++journey->numsystems >= JUMPS_PER_BLOCK) {
        journey=journey->next;
      }
    } else {
      NSLog(@"%s: Jump Point (%@) - has no co-ordinates", __FUNCTION__, jump.system.name);
    }
  }
  
  Jump *last=[Jump lastXYZJumpOfCommander:Commander.activeCommander];
  [_renderer setPosition:last.system.x/LY_2_MTL y:last.system.y/LY_2_MTL z:last.system.z/LY_2_MTL];
  
  NSLog(@"%s: Finished loading jumps", __FUNCTION__);
  
  // Now load the systems in the galaxy... Hmm... Wonder how long 1000000 vertices take to load...
#ifdef DRAWGALAXY
  // To then get all the systems...
  
  if(galaxy.first_galaxy_block==NULL) {
    NSLog(@"%s: Loading Galaxy", __FUNCTION__);

    NSArray *allSystems=[System allSystemsInContext:MAIN_CONTEXT];
    galaxy_block_t *gb=galaxy.first_galaxy_block;
    if(gb==NULL) {
      //NSLog(@"%s: gb is NULL - allocating %lu bytes for new one", __FUNCTION__, sizeof(galaxy_block_t));
    
      if((gb=calloc(sizeof(galaxy_block_t), 1))==NULL) {
        NSLog(@"%s: Unable to calloc %lu Bytes for galaxy_block_t", __FUNCTION__, sizeof(galaxy_block_t));
        exit(-1);
      }
      galaxy.first_galaxy_block=gb;
      galaxy.last_galaxy_block=gb;
    
      galaxy.num_galaxy_blocks=1;
    }
    for (System *system in allSystems) {
      if(system.hasCoordinates) {
        if(gb==NULL) {
          //NSLog(@"%s: gb is NULL - allocating %lu bytes for new one", __FUNCTION__, sizeof(galaxy_block_t));
        
          if((gb=calloc(sizeof(galaxy_block_t), 1))==NULL) {
            NSLog(@"%s: Unable to calloc %lu Bytes for galaxy_block_t", __FUNCTION__, sizeof(galaxy_block_t));
            exit(-1);
          }
          gb->prev=galaxy.last_galaxy_block;
          gb->next=NULL;
          if(galaxy.first_galaxy_block==NULL) {
            galaxy.first_galaxy_block=gb;
          }
        
          if(galaxy.last_galaxy_block!=NULL) {
            galaxy.last_galaxy_block->next=gb;
          }
        
          galaxy.last_galaxy_block=gb;
        
          galaxy.num_galaxy_blocks++;

        }
        SystemVertex_t *point=&gb->systems[gb->numsystems];
      
        point->posx = system.x/LY_2_MTL;
        point->posy = system.y/LY_2_MTL;
        point->posz = system.z/LY_2_MTL;
        
        if((galaxy.total_systems % 100000)==0) {
          NSLog(@"%s: System %d %@ BLOCK %d SBCOUNT %d (%8.4f %8.4f %8.4f)", __FUNCTION__, galaxy.total_systems, system.name, galaxy.num_galaxy_blocks, gb->numsystems, system.x, system.y, system.z);
        }
      
        galaxy.total_systems++;

        if(++gb->numsystems >= SYSTEMS_PER_BLOCK) {
          gb=gb->next;
        }
      }
    }
  }
  NSLog(@"%s: Galaxy Loaded %d systems into %d blocks", __FUNCTION__, galaxy.total_systems, galaxy.num_galaxy_blocks);
  
#endif
}


#pragma mark -
#pragma mark map contents management

- (void)loadGalaxy {
  static dispatch_once_t onceToken;
  
  dispatch_once(&onceToken, ^{
    
    NSLog(@"%s: (%s)", __FUNCTION__, "Loading the galaxy");

    //calculate ED coordinate system
    
    [self loadCoordinateSystem];
    
    // Preload the known galaxy into a structure that we can render...
    
  });
  
  //add polyline with CMDR jumps.. In background...
  //dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
   [self loadJumpsAndWaypoints];
  //});
}


// The main game loop called by the timer above
- (void)gameloop {
  
  // tell our delegate to update itself here.
  [_delegate update:self];
  
  if(!_firstDrawOccurred) {
    // set up timing data for display since this is the first time through this loop
    _timeSinceLastDraw             = 0.0;
    _timeSinceLastDrawPreviousTime = CACurrentMediaTime();
    _firstDrawOccurred              = YES;
  } else {
    // figure out the time since we last we drew
    CFTimeInterval currentTime = CACurrentMediaTime();
    
    _timeSinceLastDraw = currentTime - _timeSinceLastDrawPreviousTime;
    
    // keep track of the time interval between draws
    _timeSinceLastDrawPreviousTime = currentTime;
  }
  
  // display (render)
  
  assert([self.view isKindOfClass:[ThreeDMapView class]]);
  
  // call the display method directly on the render view (setNeedsDisplay: has been disabled in the renderview by default)
  [(ThreeDMapView *)self.view display];
}

- (void)stopGameLoop {
  if(_displayLink) {
    // Stop the display link BEFORE releasing anything in the view
    // otherwise the display link thread may call into the view and crash
    // when it encounters something that has been release
    CVDisplayLinkStop(_displayLink);
    dispatch_source_cancel(_displaySource);
    
    CVDisplayLinkRelease(_displayLink);
    _displaySource = nil;
  }
}

- (void)setPaused:(BOOL)pause {
  if(_gameLoopPaused == pause) {
    return;
  }
  
  if(_displayLink) {
    // inform the delegate we are about to pause
    [_delegate viewController:self
                    willPause:pause];
    
    if(pause) {
      CVDisplayLinkStop(_displayLink);
    } else {
      CVDisplayLinkStart(_displayLink);
    }
  }
}

- (BOOL)isPaused {
  return _gameLoopPaused;
}

- (void)didEnterBackground:(NSNotification*)notification {
  [self setPaused:YES];
}

- (void)willEnterForeground:(NSNotification*)notification {
  [self setPaused:NO];
}



@end
